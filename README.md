# Omnitak IT Support Database

A comprehensive SQL Server database schema designed for managing an IT Support Ticketing System at Omnitak. The system includes user roles, support teams, ticket lifecycle tracking, audit logs, feedback, knowledge base, and service-level agreement (SLA) reporting.

---

## 📂 Features

- 🔐 Role-based access for Admins, Support Technicians, and Employees
- 🧑‍💻 Support team management with team leads
- 📝 Ticket management with prioritization, categorization, and lifecycle tracking
- 💬 Internal chat system per ticket
- 📚 Knowledge Base for support solutions
- ⭐ Feedback collection and rating system
- 📈 SLA compliance tracking and team performance analytics
- 🔍 Audit logs for security and action traceability

---

## ⚙️ Requirements

- Microsoft SQL Server (2016+ recommended)
- SQL Server Management Studio (SSMS) or equivalent SQL client

---

## 🚀 Setup Instructions

1. **Open SQL Server Management Studio (SSMS)**.
2. **Run `SQLQuery10.sql`**:
   - This script will:
     - Drop and recreate the `OmnitakITSupport` database
     - Create all necessary tables, indexes, views, functions, and procedures
     - Seed the database with initial users, teams, and sample ticket data

---

## 🧪 Sample Data Included

- 3 support teams (Network, Hardware, Software)
- 4 sample users (Admin, team leads, and employee)
- 1 example ticket with full interaction (chat, close, feedback)
- Knowledge base article for hardware troubleshooting

---

## 📊 Key Views

- `TicketSLAStatus`: SLA performance on tickets
- `TeamPerformance`: Overall metrics per support team
- `PasswordSecurityAudit`: Tracks last password change and hashing algorithms

---

## 🔐 Security & Audit

- All key user and ticket actions are logged in the `AuditLogs` table
- Passwords stored as hashed strings with configurable hash algorithms

---

## 📌 Notes

- This system is **modular** and can be extended to include:
  - Email notifications
  - Ticket escalation workflows
  - Mobile and web frontends
- Foreign key constraints and indexes are optimized for performance and referential integrity

---

## 📄 License

This project is for educational and internal use. Feel free to adapt or extend with credit.

---

## 👤 Author
Sinqobile Nzimande

---

