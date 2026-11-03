ALTER PROCEDURE dbo.User_Delete @Login nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.[User] WHERE [Login] = @Login;
    SELECT CAST(@@ROWCOUNT AS int) AS [AffectedRows];
END;
