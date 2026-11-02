-- Repeatable schema updates run in a transaction under an application lock.
-- Add future, non-destructive schema changes here with existence checks.
IF OBJECT_ID(N'dbo.[User]', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.[User]
    (
        [Name] nvarchar(100) NOT NULL,
        [Login] nvarchar(100) COLLATE Latin1_General_100_CI_AS NOT NULL,
        [Age] int NOT NULL,
        CONSTRAINT [PK_User] PRIMARY KEY ([Login])
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'dbo.[User]') AND name = N'CK_User_Name')
    ALTER TABLE dbo.[User] WITH CHECK ADD CONSTRAINT [CK_User_Name]
        CHECK (LEN(LTRIM(RTRIM([Name]))) > 0);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'dbo.[User]') AND name = N'CK_User_Login')
    ALTER TABLE dbo.[User] WITH CHECK ADD CONSTRAINT [CK_User_Login]
        CHECK (LEN([Login]) > 0 AND DATALENGTH([Login]) = DATALENGTH(LTRIM(RTRIM([Login]))));

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE parent_object_id = OBJECT_ID(N'dbo.[User]') AND name = N'CK_User_Age')
    ALTER TABLE dbo.[User] WITH CHECK ADD CONSTRAINT [CK_User_Age] CHECK ([Age] >= 0);
