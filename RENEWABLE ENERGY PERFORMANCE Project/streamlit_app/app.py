# app.py  -  Renewable Energy Data Explorer (simple Streamlit app)
#
# What it does: shows the cleaned energy data with filters, numbers, charts and a table.
# How to run :  streamlit run streamlit_app/app.py        (run it from the main project folder)
#               If "streamlit" is not recognized, use:  python -m streamlit run streamlit_app/app.py
#
# The app needs the file  cleaned_energy_data.csv  (it is kept in the "data" folder).

import os
import pandas as pd
import streamlit as st

# ------------------------------------------------------------------
# 1. Page settings and a little colour
# ------------------------------------------------------------------
st.set_page_config(page_title="Renewable Energy Explorer", page_icon="⚡", layout="wide")

st.markdown(
    """
    <style>
    .banner {background: linear-gradient(90deg, #1b6ca8, #3bb273); padding: 22px 28px;
             border-radius: 14px; margin-bottom: 18px;}
    .banner h1 {color: white; margin: 0; font-size: 34px;}
    .banner p {color: #eaf6ff; margin: 4px 0 0 0; font-size: 16px;}
    div[data-testid="stMetric"] {background-color: #eef6ff; border-left: 6px solid #2e86ab;
             padding: 12px 16px; border-radius: 10px;}
    div[data-testid="stMetric"] * {color: #1b2a41 !important;}
    </style>
    <div class="banner">
        <h1>⚡ Renewable Energy Performance Explorer</h1>
        <p>Solar, Wind and Hydro plants - year 2025</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# ------------------------------------------------------------------
# 2. Find and load the data file
# ------------------------------------------------------------------
CSV_NAME = "cleaned_energy_data.csv"
PROJECT_FOLDER = r"D:\RENEWABLE ENERGY PERFORMANCE Project"


def find_csv():
    """Look for the CSV file in the places where it can be. Return the path, or None."""
    app_folder = os.path.dirname(os.path.abspath(__file__))
    main_folder = os.path.dirname(app_folder)
    places = [
        os.path.join(main_folder, "data"),                 # normal place: project folder / data
        main_folder,                                       # CSV kept in the main folder
        app_folder,                                        # CSV kept next to app.py
        os.path.join(PROJECT_FOLDER, "data"),
        PROJECT_FOLDER,
        os.getcwd(),
    ]
    for folder in places:
        path = os.path.join(folder, CSV_NAME)
        if os.path.exists(path):
            return path
    return None


@st.cache_data
def load_file(path):
    return pd.read_csv(path, parse_dates=["Date"])


csv_path = find_csv()

if csv_path is not None:
    df = load_file(csv_path)
else:
    # File not found: show a clear message and let the user upload the file
    st.error(f"Could not find **{CSV_NAME}**.")
    st.write("Keep `cleaned_energy_data.csv` in the **data** folder of the project, or upload the file below.")
    uploaded = st.file_uploader("Upload cleaned_energy_data.csv", type="csv")
    if uploaded is None:
        st.stop()
    df = pd.read_csv(uploaded, parse_dates=["Date"])

df["Max_Energy"] = df["Installed_Capacity_MW"] * 4      # most energy a plant can make in one 4-hour block

# ------------------------------------------------------------------
# 3. Filters (left side)
# ------------------------------------------------------------------
st.sidebar.header("🔎 Filters")

types = st.sidebar.multiselect("Energy type", ["Solar", "Wind", "Hydro"], default=["Solar", "Wind", "Hydro"])
all_regions = sorted(df["Region"].unique())
regions = st.sidebar.multiselect("Region", all_regions, default=all_regions)

# the plant list changes with the energy type and region chosen above
plant_options = sorted(df[df["Energy_Type"].isin(types) & df["Region"].isin(regions)]["Plant_Name"].unique())
plants = st.sidebar.multiselect("Plant", plant_options, default=plant_options)

first_day = df["Date"].min().date()
last_day = df["Date"].max().date()
dates = st.sidebar.date_input("Date range", (first_day, last_day), min_value=first_day, max_value=last_day)
if len(dates) != 2:
    st.sidebar.info("Please pick both a start date and an end date.")
    st.stop()

all_statuses = sorted(df["Plant_Status"].unique())
statuses = st.sidebar.multiselect("Plant status", all_statuses, default=all_statuses)

data = df[
    df["Energy_Type"].isin(types)
    & df["Region"].isin(regions)
    & df["Plant_Name"].isin(plants)
    & (df["Date"] >= pd.Timestamp(dates[0]))
    & (df["Date"] <= pd.Timestamp(dates[1]))
    & df["Plant_Status"].isin(statuses)
]

if data.empty:
    st.warning("No data for these filters. Please change the filters on the left.")
    st.stop()

# ------------------------------------------------------------------
# 4. Main numbers
# ------------------------------------------------------------------
total_energy = data["Energy_Generated_MWh"].sum()
utilization = total_energy / data["Max_Energy"].sum() * 100

c1, c2, c3, c4, c5, c6, c7 = st.columns(7)
c1.metric("Filtered records", f"{len(data):,}")
c2.metric("Total energy", f"{total_energy / 1000:,.1f} GWh")
c3.metric("Average efficiency", f"{data['Efficiency_Percent'].mean():.2f} %")
c4.metric("Operating cost", f"₹ {data['Operating_Cost'].sum() / 10000000:,.1f} crore")
c5.metric("Capacity utilization", f"{utilization:.1f} %", help="Energy generated / maximum possible energy x 100")
c6.metric("Total revenue", f"₹ {data['Revenue'].sum() / 10000000:,.1f} crore")
c7.metric("Total downtime", f"{data['Downtime_Hours'].sum():,.0f} hours")

st.write("")
tab1, tab2, tab3 = st.tabs(["📊 Overview", "🏭 Plants", "📋 Data table"])

# ------------------------------------------------------------------
# 5. Tab 1 - Overview charts
# ------------------------------------------------------------------
with tab1:
    left, right = st.columns(2)

    with left:
        st.subheader("Energy in each month (GWh)")
        monthly = data.groupby([data["Date"].dt.month, "Energy_Type"])["Energy_Generated_MWh"].sum().unstack() / 1000
        colours = {"Solar": "#F2A900", "Wind": "#2E86AB", "Hydro": "#3BB273"}
        monthly = monthly[[t for t in colours if t in monthly.columns]]       # keep colour order
        st.line_chart(monthly, color=[colours[t] for t in monthly.columns])

    with right:
        st.subheader("Energy by region (GWh)")
        by_region = data.groupby("Region")["Energy_Generated_MWh"].sum().sort_values(ascending=False) / 1000
        st.bar_chart(by_region, color="#1b6ca8")

    left, right = st.columns(2)

    with left:
        st.subheader("Top 10 plants (GWh)")
        top10 = data.groupby("Plant_Name")["Energy_Generated_MWh"].sum().sort_values(ascending=False).head(10) / 1000
        st.bar_chart(top10, color="#3BB273")

    with right:
        st.subheader("Utilization by energy type (%)")
        by_type = data.groupby("Energy_Type")[["Energy_Generated_MWh", "Max_Energy"]].sum()
        st.bar_chart(by_type["Energy_Generated_MWh"] / by_type["Max_Energy"] * 100, color="#F2A900")

# ------------------------------------------------------------------
# 6. Tab 2 - Plants
# ------------------------------------------------------------------
with tab2:
    plant_table = data.groupby(["Plant_Name", "Energy_Type", "Region"]).agg(
        Energy_GWh=("Energy_Generated_MWh", lambda x: x.sum() / 1000),
        Efficiency=("Efficiency_Percent", "mean"),
        Availability=("Availability_Percent", "mean"),
        Downtime_Hours=("Downtime_Hours", "sum"),
        Energy_MWh=("Energy_Generated_MWh", "sum"),
        Max_Energy=("Max_Energy", "sum"),
    ).reset_index()
    plant_table["Utilization"] = plant_table["Energy_MWh"] / plant_table["Max_Energy"] * 100
    plant_table = plant_table.sort_values("Energy_GWh", ascending=False)

    st.subheader("All plants")
    st.dataframe(
        plant_table[["Plant_Name", "Energy_Type", "Region", "Energy_GWh", "Utilization",
                     "Efficiency", "Availability", "Downtime_Hours"]].round(1),
        hide_index=True,
    )

    st.subheader("Look at one plant")
    chosen = st.selectbox("Choose a plant", plant_table["Plant_Name"])
    one_plant = data[data["Plant_Name"] == chosen]
    daily = one_plant.groupby("Date")["Energy_Generated_MWh"].sum()
    st.write(f"Daily energy of **{chosen}** (MWh)")
    st.line_chart(daily, color="#2E86AB")

# ------------------------------------------------------------------
# 7. Tab 3 - Data table and download
# ------------------------------------------------------------------
with tab3:
    st.write(f"{len(data):,} rows match your filters. Showing the first 200 rows.")
    st.dataframe(data.drop(columns=["Max_Energy"]).head(200), hide_index=True)

    csv_bytes = data.drop(columns=["Max_Energy"]).to_csv(index=False).encode("utf-8")
    st.download_button("⬇️ Download these rows as CSV", csv_bytes, "filtered_energy_data.csv", "text/csv")
