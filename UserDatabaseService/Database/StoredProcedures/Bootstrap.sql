-- Only explicit setup runs this batch, under the shared transaction-owned schema lock.
IF TYPE_ID(N'dbo.UserLoginList') IS NULL
    EXEC(N'CREATE TYPE dbo.UserLoginList AS TABLE
        ([Login] nvarchar(100) COLLATE Latin1_General_100_CI_AS NOT NULL);');

DECLARE @typeObject int =
    (SELECT type_table_object_id FROM sys.table_types
     WHERE user_type_id = TYPE_ID(N'dbo.UserLoginList'));
IF @typeObject IS NULL
    OR (SELECT COUNT(*) FROM sys.columns WHERE object_id = @typeObject) <> 1
    OR NOT EXISTS (SELECT 1 FROM sys.columns
        WHERE object_id = @typeObject AND column_id = 1 AND name = N'Login'
          AND system_type_id = TYPE_ID(N'nvarchar') AND max_length = 200
          AND is_nullable = 0 AND collation_name = N'Latin1_General_100_CI_AS')
    OR EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = @typeObject AND is_unique = 1)
    THROW 50002, 'The existing user login-list type is incompatible with database setup.', 1;

IF OBJECT_ID(N'dbo.User_GetAll', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.User_GetAll AS RETURN 0;');
IF OBJECT_ID(N'dbo.User_GetByLogin', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.User_GetByLogin AS RETURN 0;');
IF OBJECT_ID(N'dbo.User_GetByLogins', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.User_GetByLogins AS RETURN 0;');
IF OBJECT_ID(N'dbo.User_Create', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.User_Create AS RETURN 0;');
IF OBJECT_ID(N'dbo.User_Update', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.User_Update AS RETURN 0;');
IF OBJECT_ID(N'dbo.User_Delete', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.User_Delete AS RETURN 0;');
