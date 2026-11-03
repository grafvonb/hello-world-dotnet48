ALTER PROCEDURE dbo.User_Create @Name nvarchar(100), @Login nvarchar(100), @Age int
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.[User] ([Name], [Login], [Age]) VALUES (@Name, @Login, @Age);
END;
