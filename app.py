"""
AUB Mediterraneo Admissions Database - INDE 513 Project Phase II website
Flask + SQLite. Run:  pip install -r requirements.txt  then  python app.py
"""
import os, re, sqlite3
from datetime import date
from flask import Flask, g, render_template, request, redirect, url_for, flash, abort

BASE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.environ.get('DB_PATH', os.path.join(BASE, 'admissions.db'))

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'inde513-dev-key')


# ---------------------------------------------------------------- database
def init_db(force=False):
    """Create the database from the project SQL files if it does not exist yet."""
    if os.path.exists(DB_PATH) and not force:
        return
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    con.execute('PRAGMA foreign_keys = ON')
    for f in ('01_schema.sql', '02_sample_data.sql'):
        with open(os.path.join(BASE, 'sql', f), encoding='utf-8') as fh:
            con.executescript(fh.read())
    con.commit()
    con.close()


def db():
    if 'db' not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute('PRAGMA foreign_keys = ON')   # required for every connection
    return g.db


@app.teardown_appcontext
def close_db(exc):
    con = g.pop('db', None)
    if con is not None:
        con.close()


def q(sql, args=(), one=False):
    cur = db().execute(sql, args)
    rows = cur.fetchall()
    return (rows[0] if rows else None) if one else rows


def friendly(e):
    """Turn a SQLite constraint error into a readable message."""
    msg = str(e)
    if 'UNIQUE constraint failed: Applicant.PassportNo' in msg:
        return 'Another applicant already uses this passport number (BR24).'
    if 'UNIQUE constraint failed: Applicant.Email' in msg:
        return 'Another applicant already uses this email.'
    if 'Application.ApplicantID, Application.ProgramID, Application.AdmissionYear' in msg:
        return 'This applicant already applied to this program in this admission cycle (BR3).'
    if 'UNIQUE constraint failed: Review' in msg:
        return 'This professor has already reviewed this application (BR16).'
    if 'UNIQUE constraint failed: AdmissionDecision.ApplicationID' in msg:
        return 'This application already has a decision (BR18).'
    if 'UNIQUE constraint failed: FinancialAidAward.ApplicationID' in msg:
        return 'This application already has an aid offer (BR20).'
    if 'AdmissionRound' in msg and 'CHECK' in msg:
        return 'Early round is only allowed up to 15 December of the year before the admission year (BR6).'
    if 'SubmissionDate <' in msg:
        return 'The submission date must be before 1 August of the admission year.'
    if 'CHECK constraint failed' in msg:
        return 'A value is outside its allowed range or choices: ' + msg.split('failed:')[-1].strip()
    if 'FOREIGN KEY' in msg:
        return 'This record points to something that does not exist.'
    return msg


# ---------------------------------------------------------------- pages
@app.route('/')
def index():
    stats = {
        'applicants': q('SELECT COUNT(*) n FROM Applicant', one=True)['n'],
        'applications': q('SELECT COUNT(*) n FROM Application', one=True)['n'],
        'open': q("SELECT COUNT(*) n FROM Application WHERE ApplicationStatus <> 'Decided'", one=True)['n'],
        'accepted': q("SELECT COUNT(*) n FROM AdmissionDecision WHERE DecisionType = 'Accepted'", one=True)['n'],
    }
    by_program = q('''SELECT p.ProgramID, p.ProgramName, p.DegreeLevel,
                             SUM(CASE WHEN ap.AdmissionYear = 2026 THEN 1 ELSE 0 END) AS y2026,
                             SUM(CASE WHEN ap.AdmissionYear = 2027 THEN 1 ELSE 0 END) AS y2027
                      FROM Program p LEFT JOIN Application ap ON ap.ProgramID = p.ProgramID
                      GROUP BY p.ProgramID ORDER BY p.DegreeLevel DESC, p.ProgramID''')
    waiting = q('''SELECT s.*, a.FirstName || ' ' || a.LastName AS ApplicantName
                   FROM vApplicationSummary s JOIN Applicant a ON a.ApplicantID = s.ApplicantID
                   WHERE s.ApplicationStatus <> 'Decided'
                   ORDER BY s.DaysSinceSubmission DESC LIMIT 6''')
    return render_template('index.html', stats=stats, by_program=by_program, waiting=waiting)


@app.route('/applicants')
def applicants():
    term = request.args.get('q', '').strip()
    sql = '''SELECT v.*, (SELECT COUNT(*) FROM Application ap WHERE ap.ApplicantID = v.ApplicantID) AS NumApps,
                    (SELECT GROUP_CONCAT(CountryCode, ', ') FROM ApplicantNationality n WHERE n.ApplicantID = v.ApplicantID) AS Nats
             FROM vApplicant v'''
    args = ()
    if term:
        sql += ''' WHERE v.FirstName LIKE ? OR v.LastName LIKE ? OR v.PassportNo LIKE ? OR v.Email LIKE ?
                   OR CAST(v.ApplicantID AS TEXT) = ?'''
        like = f'%{term}%'
        args = (like, like, like, like, term)
    sql += ' ORDER BY v.LastName, v.FirstName'
    return render_template('applicants.html', rows=q(sql, args), term=term)


@app.route('/applicants/<int:aid>')
def applicant_detail(aid):
    a = q('SELECT * FROM vApplicant WHERE ApplicantID = ?', (aid,), one=True)
    if not a:
        abort(404)
    phones = q('SELECT PhoneNumber FROM ApplicantPhone WHERE ApplicantID = ?', (aid,))
    nats = q('SELECT CountryCode FROM ApplicantNationality WHERE ApplicantID = ?', (aid,))
    apps = q('''SELECT s.*, p.ProgramName, ad.DecisionType
                FROM vApplicationSummary s JOIN Program p ON p.ProgramID = s.ProgramID
                LEFT JOIN AdmissionDecision ad ON ad.ApplicationID = s.ApplicationID
                WHERE s.ApplicantID = ? ORDER BY s.AdmissionYear DESC, s.ApplicationID''', (aid,))
    return render_template('applicant_detail.html', a=a, phones=phones, nats=nats, apps=apps)


@app.route('/applicants/new', methods=['GET', 'POST'])
def applicant_new():
    f = request.form
    if request.method == 'POST':
        phones = [x.strip() for x in f.get('phones', '').split(',') if x.strip()]
        nats = [x.strip().upper() for x in f.get('nats', '').split(',') if x.strip()]
        if not phones or not nats:
            flash('At least one phone number and one nationality are required (BR1, BR2).', 'error')
            return render_template('applicant_new.html', f=f)
        con = db()
        try:
            with con:   # one transaction: all three tables or nothing
                cur = con.execute('''INSERT INTO Applicant (PassportNo, FirstName, MiddleName, LastName, DateOfBirth, Email)
                                     VALUES (?, ?, ?, ?, ?, ?)''',
                                  (f['passport'].strip(), f['first'].strip(), f.get('middle', '').strip() or None,
                                   f['last'].strip(), f['dob'], f['email'].strip()))
                new_id = cur.lastrowid
                for ph in phones:
                    con.execute('INSERT INTO ApplicantPhone (ApplicantID, PhoneNumber) VALUES (?, ?)', (new_id, ph))
                for n in nats:
                    con.execute('INSERT INTO ApplicantNationality (ApplicantID, CountryCode) VALUES (?, ?)', (new_id, n))
            flash(f'Applicant {new_id} added.', 'ok')
            return redirect(url_for('applicant_detail', aid=new_id))
        except sqlite3.Error as e:
            flash(friendly(e), 'error')
    return render_template('applicant_new.html', f=f)


@app.route('/applications')
def applications():
    year = request.args.get('year', '')
    prog = request.args.get('program', '')
    status = request.args.get('status', '')
    rnd = request.args.get('round', '')
    sql = '''SELECT s.*, a.FirstName || ' ' || a.LastName AS ApplicantName, p.ProgramName, ad.DecisionType
             FROM vApplicationSummary s
             JOIN Applicant a ON a.ApplicantID = s.ApplicantID
             JOIN Program p ON p.ProgramID = s.ProgramID
             LEFT JOIN AdmissionDecision ad ON ad.ApplicationID = s.ApplicationID WHERE 1 = 1'''
    args = []
    if year:   sql += ' AND s.AdmissionYear = ?';     args.append(year)
    if prog:   sql += ' AND s.ProgramID = ?';         args.append(prog)
    if status: sql += ' AND s.ApplicationStatus = ?'; args.append(status)
    if rnd:    sql += ' AND s.AdmissionRound = ?';    args.append(rnd)
    sql += ' ORDER BY s.AdmissionYear DESC, s.SubmissionDate'
    return render_template('applications.html', rows=q(sql, args), programs=q('SELECT * FROM Program ORDER BY ProgramID'),
                           years=q('SELECT DISTINCT AdmissionYear FROM Application ORDER BY 1 DESC'),
                           sel=dict(year=year, program=prog, status=status, round=rnd))


@app.route('/applications/<int:app_id>')
def application_detail(app_id):
    s = q('''SELECT s.*, a.FirstName || ' ' || a.LastName AS ApplicantName, p.ProgramName, p.DegreeLevel,
                    d.DepartmentName, p.DepartmentID
             FROM vApplicationSummary s JOIN Applicant a ON a.ApplicantID = s.ApplicantID
             JOIN Program p ON p.ProgramID = s.ProgramID JOIN Department d ON d.DepartmentID = p.DepartmentID
             WHERE s.ApplicationID = ?''', (app_id,), one=True)
    if not s:
        abort(404)
    docs = q('SELECT * FROM ApplicationDocument WHERE ApplicationID = ? ORDER BY DocumentNo', (app_id,))
    reviews = q('''SELECT r.*, pr.FirstName || ' ' || pr.LastName AS ProfessorName
                   FROM Review r JOIN Professor pr ON pr.ProfessorID = r.ProfessorID
                   WHERE r.ApplicationID = ? ORDER BY r.ReviewDate''', (app_id,))
    decision = q('SELECT * FROM AdmissionDecision WHERE ApplicationID = ?', (app_id,), one=True)
    aid = q('SELECT * FROM FinancialAidAward WHERE ApplicationID = ?', (app_id,), one=True)
    missing = q('''SELECT r.RequirementName FROM ProgramRequirement pr JOIN Requirement r ON r.RequirementID = pr.RequirementID
                   WHERE pr.ProgramID = ? AND pr.IsMandatory = 'Y' ORDER BY r.RequirementID''', (s['ProgramID'],))
    profs = q('''SELECT * FROM Professor WHERE DepartmentID = ?
                 AND ProfessorID NOT IN (SELECT ProfessorID FROM Review WHERE ApplicationID = ?)
                 ORDER BY LastName''', (s['DepartmentID'], app_id))
    return render_template('application_detail.html', s=s, docs=docs, reviews=reviews, decision=decision,
                           aid=aid, required=missing, profs=profs, today=date.today().isoformat())


@app.route('/applications/new', methods=['GET', 'POST'])
def application_new():
    f = request.form
    if request.method == 'POST':
        try:
            with db() as con:
                cur = con.execute('''INSERT INTO Application (ApplicantID, ProgramID, AdmissionYear, SubmissionDate, AdmissionRound)
                                     VALUES (?, ?, ?, ?, ?)''',
                                  (f['applicant'], f['program'], f['year'], f['subdate'], f['round']))
            flash(f'Application {cur.lastrowid} submitted.', 'ok')
            return redirect(url_for('application_detail', app_id=cur.lastrowid))
        except sqlite3.Error as e:
            flash(friendly(e), 'error')
    return render_template('application_new.html', f=f,
                           applicants=q('SELECT ApplicantID, FirstName, LastName FROM Applicant ORDER BY LastName'),
                           programs=q("SELECT * FROM Program WHERE ProgramStatus = 'Active' ORDER BY ProgramID"),
                           today=date.today().isoformat())


@app.route('/applications/<int:app_id>/review', methods=['POST'])
def review_add(app_id):
    f = request.form
    try:
        with db() as con:
            con.execute('''INSERT INTO Review (ProfessorID, ApplicationID, ReviewScore, ReviewDate, Comments)
                           VALUES (?, ?, ?, ?, ?)''',
                        (f['professor'], app_id, f['score'], f['rdate'], f.get('comments', '').strip() or None))
            con.execute("UPDATE Application SET ApplicationStatus = 'Under Review' WHERE ApplicationID = ? AND ApplicationStatus = 'Submitted'", (app_id,))
        flash('Review saved.', 'ok')
    except sqlite3.Error as e:
        flash(friendly(e), 'error')
    return redirect(url_for('application_detail', app_id=app_id))


@app.route('/applications/<int:app_id>/decision', methods=['POST'])
def decision_add(app_id):
    f = request.form
    try:
        with db() as con:
            con.execute('INSERT INTO AdmissionDecision (DecisionType, DecisionDate, ApplicationID) VALUES (?, ?, ?)',
                        (f['dtype'], f['ddate'], app_id))
        flash('Decision recorded.', 'ok')
    except sqlite3.Error as e:
        flash(friendly(e), 'error')
    return redirect(url_for('application_detail', app_id=app_id))


@app.route('/applications/<int:app_id>/aid', methods=['POST'])
def aid_add(app_id):
    f = request.form
    try:
        with db() as con:
            con.execute('INSERT INTO FinancialAidAward (AidType, AidPercentage, ApplicationID) VALUES (?, ?, ?)',
                        (f['aidtype'], f['pct'], app_id))
        flash('Aid offer saved.', 'ok')
    except sqlite3.Error as e:
        flash(friendly(e), 'error')
    return redirect(url_for('application_detail', app_id=app_id))


# Report page: runs the queries from sql/03_queries.sql
def load_queries():
    with open(os.path.join(BASE, 'sql', '03_queries.sql'), encoding='utf-8') as fh:
        txt = fh.read()
    out = []
    for blk in re.split(r'\n(?=-- Q\d+)', txt)[1:]:
        lines = blk.strip().splitlines()
        title = lines[0][3:].strip()
        desc = ' '.join(l[3:].strip() for l in lines[1:] if l.startswith('--'))
        sql = '\n'.join(l for l in lines if not l.startswith('--')).strip()
        out.append({'id': title.split()[0], 'title': title, 'desc': desc, 'sql': sql})
    return out


@app.route('/reports')
def reports():
    qs = load_queries()
    pick = request.args.get('q', 'Q4')
    cur = next((x for x in qs if x['id'] == pick), qs[0])
    c = db().execute(cur['sql'])
    cols = [d[0] for d in c.description]
    return render_template('reports.html', qs=qs, cur=cur, cols=cols, rows=c.fetchall())


@app.route('/reset', methods=['POST'])
def reset():
    init_db(force=True)
    flash('Database reset to the original sample data.', 'ok')
    return redirect(url_for('index'))


init_db()

if __name__ == '__main__':
    app.run(debug=True, port=int(os.environ.get('PORT', 5000)))
