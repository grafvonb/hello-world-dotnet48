ALTER PROCEDURE dbo.User_GetByLogins @Logins dbo.UserLoginList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.[Name], u.[Login], u.[Age]
    FROM dbo.[User] AS u
    WHERE EXISTS (SELECT 1 FROM @Logins AS wanted WHERE wanted.[Login] = u.[Login])
    ORDER BY u.[Login];
END;
