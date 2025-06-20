USE master;
GO

-- Forcefully close all connections and drop database
IF DB_ID('OmnitakITSupport') IS NOT NULL
BEGIN
    DECLARE @killSql NVARCHAR(MAX) = ''
    SELECT @killSql = @killSql + 'KILL ' + CAST(session_id AS NVARCHAR(10)) + ';'
    FROM sys.dm_exec_sessions
    WHERE database_id = DB_ID('OmnitakITSupport')
    
    IF @killSql <> '' EXEC sp_executesql @killSql
    DROP DATABASE IF EXISTS OmnitakITSupport
END
GO

CREATE DATABASE OmnitakITSupport;
GO

USE OmnitakITSupport;
GO

-- Core Tables
CREATE TABLE Roles (
    RoleID INT IDENTITY(1,1) PRIMARY KEY,
    RoleName NVARCHAR(50) NOT NULL UNIQUE CHECK (RoleName IN ('Admin', 'Support Technician', 'Employee'))
);

CREATE TABLE SupportTeams (
    TeamID INT IDENTITY(1,1) PRIMARY KEY,
    TeamName NVARCHAR(100) NOT NULL UNIQUE,
    Description NVARCHAR(255),
    Specialization NVARCHAR(100),
    TeamLeadID INT NULL
);

CREATE TABLE Users (
    UserID INT IDENTITY(1,1) PRIMARY KEY,
    Email NVARCHAR(255) NOT NULL UNIQUE,
    PasswordHash NVARCHAR(128) NOT NULL,
    HashAlgorithm NVARCHAR(20) NOT NULL DEFAULT 'bcrypt12',
    FullName NVARCHAR(100) NOT NULL,
    RoleID INT NOT NULL FOREIGN KEY REFERENCES Roles(RoleID),
    TeamID INT NULL,
    Department NVARCHAR(50) NOT NULL DEFAULT 'IT' 
        CHECK (Department IN ('HR', 'Finance', 'Operations', 'IT')),
    CreatedAt DATETIME DEFAULT GETDATE()
);

-- Add FKs after both tables exist
ALTER TABLE SupportTeams
ADD CONSTRAINT FK_SupportTeams_TeamLeadID
FOREIGN KEY (TeamLeadID) REFERENCES Users(UserID) ON DELETE SET NULL;

ALTER TABLE Users
ADD CONSTRAINT FK_Users_TeamID
FOREIGN KEY (TeamID) REFERENCES SupportTeams(TeamID) ON DELETE SET NULL;

-- Ticket Management
CREATE TABLE Tickets (
    TicketID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX) NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Open' 
        CHECK (Status IN ('Open', 'In Progress', 'Closed', 'On Hold')),
    Priority INT NOT NULL CHECK (Priority BETWEEN 1 AND 5) DEFAULT 3,
    Category NVARCHAR(50) NOT NULL 
        CHECK (Category IN ('Hardware', 'Software', 'Email', 'Network', 'Account', 'Other')),
    CreatedBy INT NOT NULL FOREIGN KEY REFERENCES Users(UserID),
    AssignedTo INT NULL FOREIGN KEY REFERENCES Users(UserID) ON DELETE SET NULL,
    CreatedAt DATETIME DEFAULT GETDATE(),
    ClosedAt DATETIME
);

CREATE TABLE TicketTimeline (
    TimelineID INT IDENTITY(1,1) PRIMARY KEY,
    TicketID INT NOT NULL FOREIGN KEY REFERENCES Tickets(TicketID) ON DELETE CASCADE,
    ExpectedResolution DATETIME NOT NULL,
    ActualResolution DATETIME
);

CREATE TABLE ChatMessages (
    MessageID INT IDENTITY(1,1) PRIMARY KEY,
    TicketID INT NOT NULL FOREIGN KEY REFERENCES Tickets(TicketID) ON DELETE CASCADE,
    UserID INT NOT NULL FOREIGN KEY REFERENCES Users(UserID),
    Message NVARCHAR(MAX) NOT NULL,
    SentAt DATETIME DEFAULT GETDATE(),
    ReadAt DATETIME NULL
);

-- Knowledge Base
CREATE TABLE KnowledgeBase (
    ArticleID INT IDENTITY(1,1) PRIMARY KEY,
    Title NVARCHAR(200) NOT NULL,
    Content NVARCHAR(MAX) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    CreatedBy INT NOT NULL FOREIGN KEY REFERENCES Users(UserID),
    LastUpdatedBy INT NULL FOREIGN KEY REFERENCES Users(UserID),
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME NULL,
    HelpfulCount INT DEFAULT 0
);

-- Feedback System
CREATE TABLE Feedback (
    FeedbackID INT IDENTITY(1,1) PRIMARY KEY,
    TicketID INT NOT NULL FOREIGN KEY REFERENCES Tickets(TicketID) ON DELETE CASCADE,
    UserID INT NOT NULL FOREIGN KEY REFERENCES Users(UserID),
    Rating INT NOT NULL CHECK (Rating BETWEEN 1 AND 5),
    Comment NVARCHAR(500) NULL,
    CreatedAt DATETIME DEFAULT GETDATE(),
    CONSTRAINT UC_Feedback UNIQUE (TicketID, UserID)
);

-- Audit & Security
CREATE TABLE AuditLogs (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT NULL FOREIGN KEY REFERENCES Users(UserID) ON DELETE SET NULL,
    Action NVARCHAR(50) NOT NULL,
    TargetType NVARCHAR(50) NOT NULL,
    TargetID INT NULL,
    Details NVARCHAR(500) NULL,
    IPAddress NVARCHAR(50) NULL,
    PerformedAt DATETIME DEFAULT GETDATE()
);

CREATE TABLE PasswordResets (
    Token UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    UserID INT NOT NULL FOREIGN KEY REFERENCES Users(UserID) ON DELETE CASCADE,
    ExpiresAt DATETIME NOT NULL,
    IsUsed BIT DEFAULT 0
);
GO

-- Indexes for Performance
CREATE INDEX IDX_Tickets_Status ON Tickets(Status);
CREATE INDEX IDX_Tickets_Category ON Tickets(Category);
CREATE INDEX IDX_Tickets_AssignedTo ON Tickets(AssignedTo);
CREATE INDEX IDX_Tickets_CreatedBy ON Tickets(CreatedBy);
CREATE INDEX IDX_Users_Department ON Users(Department);
CREATE INDEX IDX_TicketTimeline_Resolution ON TicketTimeline(ExpectedResolution, ActualResolution);
CREATE INDEX IDX_KnowledgeBase_Category ON KnowledgeBase(Category);
CREATE INDEX IDX_AuditLogs_Action ON AuditLogs(Action);
CREATE INDEX IDX_ChatMessages_Ticket ON ChatMessages(TicketID);
CREATE INDEX IDX_ChatMessages_ReadStatus ON ChatMessages(ReadAt);
GO

-- Filtered unique index for team lead
CREATE UNIQUE INDEX UIDX_SupportTeams_TeamLead 
ON SupportTeams(TeamLeadID) 
WHERE TeamLeadID IS NOT NULL;
GO

-- Stored Procedures
CREATE PROCEDURE CreateTicket
    @Title NVARCHAR(200),
    @Description NVARCHAR(MAX),
    @Priority INT,
    @Category NVARCHAR(50),
    @CreatedBy INT,
    @ExpectedResolutionHours INT = 48
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO Tickets (Title, Description, Priority, Category, CreatedBy)
        VALUES (@Title, @Description, @Priority, @Category, @CreatedBy);

        DECLARE @NewTicketID INT = SCOPE_IDENTITY();
        DECLARE @Expected DATETIME = DATEADD(HOUR, @ExpectedResolutionHours, GETDATE());

        INSERT INTO TicketTimeline (TicketID, ExpectedResolution)
        VALUES (@NewTicketID, @Expected);

        INSERT INTO AuditLogs (UserID, Action, TargetType, TargetID, Details)
        VALUES (@CreatedBy, 'Create Ticket', 'Ticket', @NewTicketID, 'Ticket created');

        COMMIT;
        RETURN @NewTicketID;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        THROW;
    END CATCH
END;
GO

CREATE PROCEDURE UpdateTicketStatus
    @TicketID INT,
    @NewStatus NVARCHAR(20),
    @ChangedBy INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        
        DECLARE @OldStatus NVARCHAR(20);
        SELECT @OldStatus = Status FROM Tickets WHERE TicketID = @TicketID;
        
        UPDATE Tickets 
        SET Status = @NewStatus,
            ClosedAt = CASE WHEN @NewStatus = 'Closed' THEN GETDATE() ELSE ClosedAt END
        WHERE TicketID = @TicketID;
        
        IF @NewStatus = 'Closed'
        BEGIN
            UPDATE TicketTimeline
            SET ActualResolution = GETDATE()
            WHERE TicketID = @TicketID;
        END
        
        INSERT INTO AuditLogs (UserID, Action, TargetType, TargetID, Details)
        VALUES (@ChangedBy, 'Status Change', 'Ticket', @TicketID, 
                'Changed from ' + @OldStatus + ' to ' + @NewStatus);
        
        COMMIT;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- SLA Function
CREATE FUNCTION dbo.GetSLAStatus(
    @Status NVARCHAR(20),
    @ExpectedResolution DATETIME,
    @ActualResolution DATETIME
)
RETURNS NVARCHAR(20)
AS
BEGIN
    RETURN CASE 
        WHEN @Status NOT IN ('Closed','On Hold') AND GETDATE() > @ExpectedResolution 
            THEN 'Breached'
        WHEN @Status = 'Closed' AND @ActualResolution > @ExpectedResolution 
            THEN 'Breached'
        WHEN @Status = 'Closed' AND @ActualResolution <= @ExpectedResolution 
            THEN 'On Track'
        WHEN @Status = 'On Hold'
            THEN 'Paused'
        ELSE 'Pending'
    END
END;
GO

-- View for SLA using function
CREATE VIEW TicketSLAStatus AS
SELECT 
    t.TicketID,
    t.Status,
    tl.ExpectedResolution,
    tl.ActualResolution,
    SLAStatus = dbo.GetSLAStatus(t.Status, tl.ExpectedResolution, tl.ActualResolution)
FROM Tickets t
JOIN TicketTimeline tl ON t.TicketID = tl.TicketID;
GO

-- Team assignment procedure
CREATE PROCEDURE AssignTeamLead
    @TeamID INT,
    @UserID INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        
        UPDATE SupportTeams 
        SET TeamLeadID = NULL 
        WHERE TeamLeadID = @UserID;
        
        UPDATE SupportTeams 
        SET TeamLeadID = @UserID 
        WHERE TeamID = @TeamID;
        
        UPDATE Users SET TeamID = @TeamID WHERE UserID = @UserID;
        
        INSERT INTO AuditLogs (UserID, Action, TargetType, TargetID, Details)
        VALUES (@UserID, 'Assign Lead', 'Team', @TeamID, 'Assigned as team lead');
        
        COMMIT;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        THROW;
    END CATCH
END;
GO

-- Insert base data
INSERT INTO Roles (RoleName) VALUES ('Admin'), ('Support Technician'), ('Employee');

INSERT INTO SupportTeams (TeamName, Description, Specialization) VALUES
('Network Team', 'Handles all network-related issues', 'Networking'),
('Hardware Team', 'Desktop and peripheral support', 'Hardware'),
('Software Team', 'Application support and installations', 'Software');

-- Create users
SET IDENTITY_INSERT Users ON;

INSERT INTO Users (UserID, Email, PasswordHash, HashAlgorithm, FullName, RoleID, Department) 
VALUES 
(1, 'admin@omnitak.com', '$bcrypt$v=19$m=12000,t=12$salt/hash', 'bcrypt12', 'System Admin', 1, 'IT'),
(2, 'network.lead@omnitak.com', '$bcrypt$v=19$m=12000,t=12$salt/hash', 'bcrypt12', 'John Network', 2, 'IT'),
(3, 'hardware.lead@omnitak.com', '$bcrypt$v=19$m=12000,t=12$salt/hash', 'bcrypt12', 'Emma Hardware', 2, 'IT'),
(4, 'employee@omnitak.com', '$bcrypt$v=19$m=12000,t=12$salt/hash', 'bcrypt12', 'Sarah Johnson', 3, 'Operations');

SET IDENTITY_INSERT Users OFF;

-- Assign team leads
EXEC AssignTeamLead @TeamID = 1, @UserID = 2;
EXEC AssignTeamLead @TeamID = 2, @UserID = 3;

-- Create software lead
INSERT INTO Users (Email, PasswordHash, HashAlgorithm, FullName, RoleID, Department) 
VALUES ('software.lead@omnitak.com', '$bcrypt$v=19$m=12000,t=12$salt/hash', 'bcrypt12', 'Alex Software', 2, 'IT');

DECLARE @SoftwareLeadID INT = SCOPE_IDENTITY();
EXEC AssignTeamLead @TeamID = 3, @UserID = @SoftwareLeadID;

-- Create sample ticket
DECLARE @TicketId INT;
EXEC @TicketId = CreateTicket 
    @Title='Warehouse Printer Offline', 
    @Description='Zebra printer not responding in main warehouse', 
    @Priority=2, 
    @Category='Hardware', 
    @CreatedBy=4;

-- Assign ticket
UPDATE Tickets SET AssignedTo = 3 WHERE TicketID = @TicketId;

-- Add chat messages
INSERT INTO ChatMessages (TicketID, UserID, Message) 
VALUES 
(@TicketId, 4, 'Printer shows error light, cannot print shipping labels'),
(@TicketId, 3, 'Checking printer status remotely'),
(@TicketId, 3, 'Found IP conflict, fixing now');

-- Close ticket
EXEC UpdateTicketStatus @TicketID = @TicketId, @NewStatus = 'Closed', @ChangedBy = 3;

-- Create KB article
INSERT INTO KnowledgeBase (Title, Content, Category, CreatedBy) 
VALUES (
    'Zebra Printer Troubleshooting', 
    '1. Check power and network connections
2. Reboot printer
3. Check IP configuration',
    'Hardware', 
    3
);

-- Add feedback
INSERT INTO Feedback (TicketID, UserID, Rating, Comment) 
VALUES (@TicketId, 4, 5, 'Fixed within 2 hours! Excellent support');
GO

-- Team Performance View
CREATE VIEW TeamPerformance AS
SELECT 
    st.TeamID,
    st.TeamName,
    u.FullName AS TeamLead,
    TotalTickets = COUNT(t.TicketID),
    AvgResolutionTime = AVG(DATEDIFF(MINUTE, t.CreatedAt, tl.ActualResolution)),
    SLACompliance = CAST(SUM(CASE WHEN tl.ActualResolution <= tl.ExpectedResolution THEN 1 ELSE 0 END) * 100.0 / 
                   NULLIF(COUNT(t.TicketID), 0) AS DECIMAL(5,2))
FROM SupportTeams st
LEFT JOIN Users u ON st.TeamLeadID = u.UserID
LEFT JOIN Users tech ON tech.TeamID = st.TeamID
LEFT JOIN Tickets t ON t.AssignedTo = tech.UserID
LEFT JOIN TicketTimeline tl ON t.TicketID = tl.TicketID
WHERE t.Status = 'Closed'
GROUP BY st.TeamID, st.TeamName, u.FullName;
GO

-- Security audit view
CREATE VIEW PasswordSecurityAudit AS
SELECT 
    u.UserID,
    u.Email,
    u.HashAlgorithm,
    LastPasswordChange = MAX(a.PerformedAt)
FROM Users u
LEFT JOIN AuditLogs a ON u.UserID = a.UserID AND a.Action = 'Password Update'
GROUP BY u.UserID, u.Email, u.HashAlgorithm;
GO

-- ================== VERIFICATION SECTION ==================
-- Corrected to avoid reserved keywords
SELECT 
    'SupportTeams' AS [TableName],
    TeamID,
    TeamName,
    TeamLeadID 
FROM SupportTeams;

SELECT 
    'Users' AS [TableName],
    UserID,
    FullName,
    TeamID,
    Department 
FROM Users;

SELECT 
    'Tickets' AS [TableName],
    TicketID,
    Title,
    Status 
FROM Tickets;

SELECT 
    'TicketSLAStatus' AS [ViewName],
    TicketID,
    Status,
    SLAStatus 
FROM TicketSLAStatus;

SELECT 
    'TeamPerformance' AS [ViewName],
    TeamName,
    TeamLead,
    TotalTickets,
    SLACompliance 
FROM TeamPerformance;
GO