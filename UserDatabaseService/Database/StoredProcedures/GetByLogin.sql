ALTER PROCEDURE dbo.User_GetByLogin @Login nvarchar(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [Name], [Login], [Age] FROM dbo.[User] WHERE [Login] = @Login;
END;
