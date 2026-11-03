ALTER PROCEDURE dbo.User_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [Name], [Login], [Age] FROM dbo.[User] ORDER BY [Login];
END;
