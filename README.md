# AUB Mediterraneo Admissions Database: website

INDE 513 Information Systems, Project Phase II. A small Flask website on top of the project's SQLite database.

## Features
- **Dashboard**: counts, applications per program per cycle, and the open applications that have waited longest.
- **Applicants**: list and search (name, passport number, email or ID); detail page with phones, nationalities, derived age and applications.
- **Add applicant**: one form that saves to Applicant, ApplicantPhone and ApplicantNationality in a single transaction.
- **Applications**: filter by cycle, program, status and round; detail page with documents, reviews, derived average score, decision and aid.
- **Submit application, add review, record decision, offer aid**: all go through the database constraints and triggers, so rule-breaking input is refused with a clear message (for example a 4th application in one cycle, a reviewer from another department, or aid for a rejected application).
- **Reports**: runs the 14 queries from `sql/03_queries.sql` live.

## Run it on your computer
1. Install Python 3.10 or newer.
2. Open a terminal in this `website` folder and run:
   ```
   pip install -r requirements.txt
   python app.py
   ```
3. Open http://127.0.0.1:5000 in a browser.

On first start the app builds `admissions.db` from `sql/01_schema.sql` and `sql/02_sample_data.sql`. The "Reset to sample data" button on the dashboard rebuilds it.

## Put it online with Render (free)
1. Push this `website` folder to a GitHub repository.
2. On render.com: New > Web Service > connect the repository.
3. Build command: `pip install -r requirements.txt`. Start command: `gunicorn app:app`. Instance type: Free. (`render.yaml` already holds these settings.)
4. Render gives a link like `https://aubmed-admissions.onrender.com`. Put it in the report.

Note: on Render's free plan the disk is temporary, so records added through the website disappear when the service restarts and the sample data comes back. That is fine for a demo.

## Files
- `app.py`: Flask routes and SQL
- `templates/`: HTML pages
- `static/style.css`: styling
- `sql/`: the same SQL files as the report (schema, sample data, queries)
