ALTER PROCEDURE dbo.User_Update @Name nvarchar(100), @Login nvarchar(100), @Age int
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.[User] SET [Name] = @Name, [Age] = @Age WHERE [Login] = @Login;
    SELECT CAST(@@ROWCOUNT AS int) AS [AffectedRows];
END;
