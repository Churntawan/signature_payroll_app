import os
import openpyxl
from datetime import datetime, date
from typing import Optional, List
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

EXCEL_PATH = r"C:\Users\User\Desktop\Signature_Payroll_V3_Standard.xlsx"

app = FastAPI(title="Signature Payroll API", version="2.0.0")

# Enable CORS for Flutter web / desktop
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_workbook():
    if not os.path.exists(EXCEL_PATH):
        raise HTTPException(status_code=500, detail=f"Database file not found: {EXCEL_PATH}")
    return openpyxl.load_workbook(EXCEL_PATH)

def format_date(val):
    if isinstance(val, (datetime, date)):
        return val.strftime("%Y-%m-%d")
    return str(val) if val is not None else ""

# -------------------------------------------------------------
# PYDANTIC SCHEMAS
# -------------------------------------------------------------
class AttendanceItem(BaseModel):
    date: str # YYYY-MM-DD
    ep_code: str
    nickname: str
    category: str # 'Day-off', 'Sick', 'Half-day', 'OT Days', 'Work Days'
    shift: Optional[str] = "Normal"
    units: Optional[float] = 1.0
    note: Optional[str] = ""

class AdjustmentItem(BaseModel):
    period: str # e.g. '2025-01'
    due_date: str # YYYY-MM-DD
    ep_code: str
    nickname: str
    type: str # 'Income' or 'Deduction'
    category: str # 'Advance', 'Work Permit', 'Passport / CI', 'Bonus', 'Other'
    description: Optional[str] = ""
    amount: float
    status: Optional[str] = "Pending"

class EmployeeItem(BaseModel):
    ep_code: str
    nickname: str
    status: str # 'Active' or 'Resigned'
    base_salary: float
    pay_group: str # 'Date : 1', 'Date : 10', 'Date : 20'
    stay_outside: Optional[str] = "No"
    start_date: Optional[str] = None
    resign_date: Optional[str] = None
    note: Optional[str] = ""

# -------------------------------------------------------------
# API ENDPOINTS
# -------------------------------------------------------------

@app.get("/api/health")
def health():
    return {
        "status": "online",
        "database": EXCEL_PATH,
        "exists": os.path.exists(EXCEL_PATH)
    }

@app.get("/api/periods")
def get_periods():
    wb = get_workbook()
    sheet = wb["Config_Lists"]
    periods = []
    # Column 9 is Periods
    for row in sheet.iter_rows(min_row=2, values_only=True):
        if row and len(row) >= 9 and row[8]:
            p = str(row[8]).strip()
            if p and p not in periods:
                periods.append(p)
    return {"periods": periods}

@app.get("/api/employees")
def get_employees():
    wb = get_workbook()
    sheet = wb["Employees"]
    employees = []
    for row in sheet.iter_rows(min_row=2, values_only=True):
        if row and row[0]:
            employees.append({
                "ep_code": str(row[0]).strip(),
                "nickname": str(row[1]).strip() if row[1] else "",
                "status": str(row[2]).strip() if row[2] else "Active",
                "base_salary": float(row[3]) if row[3] is not None else 0.0,
                "pay_group": str(row[4]).strip() if row[4] else "Date : 10",
                "stay_outside": str(row[5]).strip() if row[5] else "No",
                "start_date": format_date(row[6]),
                "resign_date": format_date(row[7]),
                "note": str(row[8]).strip() if len(row) > 8 and row[8] else "",
            })
    return {"employees": employees}

@app.get("/api/attendance")
def get_attendance(period: Optional[str] = None, ep_code: Optional[str] = None):
    wb = get_workbook()
    sheet = wb["Attendance_Log"]
    logs = []
    # Columns: Log ID, Date, EP Code, Nickname, Category, Shift / Team, Units, Note
    for row in sheet.iter_rows(min_row=2, values_only=True):
        if row and row[0]:
            log_date = format_date(row[1])
            curr_ep = str(row[2]).strip() if row[2] else ""
            if ep_code and curr_ep != ep_code:
                continue
            if period and not log_date.startswith(period[:7]):
                continue
            logs.append({
                "log_id": str(row[0]).strip(),
                "date": log_date,
                "ep_code": curr_ep,
                "nickname": str(row[3]).strip() if row[3] else "",
                "category": str(row[4]).strip() if row[4] else "Day-off",
                "shift": str(row[5]).strip() if row[5] else "Normal",
                "units": float(row[6]) if row[6] is not None else 1.0,
                "note": str(row[7]).strip() if len(row) > 7 and row[7] else "",
            })
    return {"attendance": logs}

@app.post("/api/attendance")
def create_attendance(item: AttendanceItem):
    wb = get_workbook()
    sheet = wb["Attendance_Log"]
    # Generate next Log ID
    next_id = sheet.max_row
    log_id = f"LOG{next_id:04d}"
    
    sheet.append([
        log_id,
        item.date,
        item.ep_code,
        item.nickname,
        item.category,
        item.shift,
        item.units,
        item.note,
    ])
    wb.save(EXCEL_PATH)
    return {"message": "Attendance record created", "log_id": log_id, "data": item.dict()}

@app.get("/api/adjustments")
def get_adjustments(period: Optional[str] = None, ep_code: Optional[str] = None):
    wb = get_workbook()
    sheet = wb["Payroll_Adjustments"]
    adjustments = []
    # Columns: Adj ID, Period, Due Date, EP Code, Nickname, Type, Category, Description, Amount, Status
    for row in sheet.iter_rows(min_row=2, values_only=True):
        if row and row[0]:
            curr_period = str(row[1]).strip() if row[1] else ""
            curr_ep = str(row[3]).strip() if row[3] else ""
            if period and curr_period != period:
                continue
            if ep_code and curr_ep != ep_code:
                continue
            adjustments.append({
                "adj_id": str(row[0]).strip(),
                "period": curr_period,
                "due_date": format_date(row[2]),
                "ep_code": curr_ep,
                "nickname": str(row[4]).strip() if row[4] else "",
                "type": str(row[5]).strip() if row[5] else "Deduction",
                "category": str(row[6]).strip() if row[6] else "Advance",
                "description": str(row[7]).strip() if row[7] else "",
                "amount": float(row[8]) if row[8] is not None else 0.0,
                "status": str(row[9]).strip() if len(row) > 9 and row[9] else "Pending",
            })
    return {"adjustments": adjustments}

@app.post("/api/adjustments")
def create_adjustment(item: AdjustmentItem):
    wb = get_workbook()
    sheet = wb["Payroll_Adjustments"]
    next_id = sheet.max_row
    adj_id = f"ADJ{next_id:04d}"
    
    sheet.append([
        adj_id,
        item.period,
        item.due_date,
        item.ep_code,
        item.nickname,
        item.type,
        item.category,
        item.description,
        item.amount,
        item.status,
    ])
    wb.save(EXCEL_PATH)
    return {"message": "Adjustment record created", "adj_id": adj_id, "data": item.dict()}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000)
