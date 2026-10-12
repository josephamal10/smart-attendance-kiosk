"""
Create (or reset the password of) an admin account.

Registering employees now needs an admin login, so the very first admin is made here:
    python scripts/create_admin.py --username admin --name "Boss Admin"
"""
import argparse
import getpass
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import SessionLocal, init_db  # noqa: E402
from models import Employee                 # noqa: E402
from auth import hash_password              # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--username", required=True)
    parser.add_argument("--name", default="Administrator")
    args = parser.parse_args()

    password = getpass.getpass("Password: ")
    if len(password) < 6 or password != getpass.getpass("Repeat password: "):
        sys.exit("Passwords must match and be at least 6 characters.")

    init_db()
    db = SessionLocal()
    try:
        emp = db.query(Employee).filter(Employee.username == args.username).first()
        if emp:
            emp.password, emp.role, emp.is_active = hash_password(password), "admin", True
            print(f"Updated existing account '{args.username}' to admin.")
        else:
            db.add(Employee(name=args.name, username=args.username,
                            password=hash_password(password), role="admin"))
            print(f"Created admin '{args.username}'.")
        db.commit()
    finally:
        db.close()


if __name__ == "__main__":
    main()
