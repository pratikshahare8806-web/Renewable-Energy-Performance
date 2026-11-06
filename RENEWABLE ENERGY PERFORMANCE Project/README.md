# Renewable Energy Performance Analytics

Data Analyst project: **Python + MySQL + Power BI + Streamlit**
Group: Samyak, Pratik, Harsh 

Project folder: `D:\RENEWABLE ENERGY PERFORMANCE Project`

## About the project
A company has 24 renewable energy plants (10 Solar, 8 Wind, 6 Hydro) in 5 regions.
We study one year of data (2025) to find which plants and energy types perform best,
how weather changes the energy, and how downtime, cost and revenue look.

The data is **made-up (synthetic)**: one row is one plant in one 4-hour block of a day
(24 plants x 365 days x 6 blocks = 52,560 rows). Mistakes were added on purpose so that we can practise cleaning.

## Folder structure
```
RENEWABLE ENERGY PERFORMANCE Project\
├── data\
│   ├── raw_energy_data.csv            messy data (52,740 rows)
│   └── cleaned_energy_data.csv        clean data (52,560 rows)
├── python\
│   ├── Data_Cleaning.ipynb            Step 1: clean the raw data
│   ├── EDA.ipynb                      Step 2: charts and insights
│   └── Performance_Analysis.ipynb     Step 3: KPIs, score and ranking
├── mysql\
│   ├── schema.sql                     database and the 4 (empty) tables
│   ├── insert_data.sql                INSERT statements with all the data
│   ├── views.sql                      views for Power BI
│   └── queries.sql                    business questions
├── powerbi\
│   └── Renewable_Energy_Performance_Analytics.pbix      5-page Power BI dashboard
├── streamlit_app\
│   └── app.py                         simple data explorer
└── README.md
```

## How to run
1. Install the packages once: `pip install pandas numpy matplotlib seaborn jupyter streamlit`
2. Run the notebooks in this order (choose *Run All*):
   `Data_Cleaning.ipynb` -> `EDA.ipynb` -> `Performance_Analysis.ipynb`
3. MySQL (8.0 or newer). Run the four files **in this order**:
```
SOURCE D:/RENEWABLE ENERGY PERFORMANCE Project/mysql/schema.sql;
SOURCE D:/RENEWABLE ENERGY PERFORMANCE Project/mysql/insert_data.sql;
SOURCE D:/RENEWABLE ENERGY PERFORMANCE Project/mysql/views.sql;
SOURCE D:/RENEWABLE ENERGY PERFORMANCE Project/mysql/queries.sql;
```
   (In MySQL use forward slashes in the path.) In MySQL Workbench use *File > Run SQL Script...* for each file.
   `schema.sql` makes the empty tables and `insert_data.sql` puts all the data in. It does not read any CSV file, so no special MySQL setting is needed.
   At the end of `insert_data.sql` you should see 24 plants and 52,560 rows in each other table.
4. Streamlit app, from the main project folder:
```
cd /d "D:\RENEWABLE ENERGY PERFORMANCE Project"
streamlit run streamlit_app/app.py
```
   If `streamlit` is not recognized, use `python -m streamlit run streamlit_app/app.py`.
   The app looks for `cleaned_energy_data.csv` in the `data` folder. If it cannot find it, it shows a message and lets you upload the file.

## Key numbers (must be the same in Python, MySQL, Power BI and Streamlit)
| Check | Value |
|---|---|
| Records | 52,560 |
| Total energy generated | 9,805,015 MWh (9,805 GWh) |
| Total revenue | INR 3,481.3 crore |
| Operating cost | INR 531.5 crore |
| Maintenance cost | INR 18.4 crore |
| Average efficiency | 85.76 % |
| Overall capacity utilization (energy / maximum energy) | 30.8 % |
| Average of the `Capacity_Utilization` column | 28.68 % |
| Installed capacity | 3,630 MW |

## Simple formulas
- Maximum energy of a record = capacity (MW) x 4 hours
- Capacity utilization (%) = energy generated / maximum energy x 100
- Availability (%) = (4 - downtime hours) / 4 x 100
- Cost per MWh = (operating cost + maintenance cost) / energy generated
- Profit margin (%) = (revenue - operating cost - maintenance cost) / revenue x 100
- **Performance Score (0-100)** = 30% utilization + 25% efficiency + 20% availability + 15% cost per MWh (lower is better) + 10% profit margin. Each part is scaled 0 to 100 inside its own energy type.
- Class: best quarter of plants = High, weakest quarter = Low, others = Medium

## Main results
- Wind gives the most energy (45.6%), then Hydro (31.2%), then Solar (23.2%).
- Vayu Wind Farm is the top plant. Kiran Solar Plant is the weakest.
- August is the best month. February is the weakest.
- Hydro is the cheapest (INR 339 per MWh). Solar is the costliest (INR 814 per MWh).
- Downtime cost at least INR 118 crore.

## Status
- [x] Data cleaning, EDA, performance analysis
- [x] MySQL schema, data insert, views, queries (tested, same results as Python)
- [x] Streamlit app (tested)
- [x] Power BI dashboard
