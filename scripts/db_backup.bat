@echo off
setlocal

for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if "%%A"=="DB_HOST" set DB_HOST=%%B
    if "%%A"=="DB_PORT" set DB_PORT=%%B
    if "%%A"=="DB_NAME" set DB_NAME=%%B
    if "%%A"=="DB_USER" set DB_USER=%%B
    if "%%A"=="DB_PASSWORD" set DB_PASSWORD=%%B
)

for /f "tokens=2 delims==" %%I in ('"wmic os get localdatetime /value"') do set DT=%%I
set TIMESTAMP=%DT:~0,8%_%DT:~8,4%

set BACKUP_DIR=%~dp0db_backups
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

set PGPASSWORD=%DB_PASSWORD%

echo Exporting schema...
pg_dump -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% --schema-only --no-owner -f "%BACKUP_DIR%\%DB_NAME%_schema_%TIMESTAMP%.sql"
if %errorlevel% neq 0 goto :error

echo Exporting data...
pg_dump -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% --data-only --no-owner --column-inserts -f "%BACKUP_DIR%\%DB_NAME%_data_%TIMESTAMP%.sql"
if %errorlevel% neq 0 goto :error

echo Exporting full backup...
pg_dump -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d %DB_NAME% --no-owner -f "%BACKUP_DIR%\%DB_NAME%_full_%TIMESTAMP%.sql"
if %errorlevel% neq 0 goto :error

REM --- Fixed-name schema dumps for Claude Project knowledge base ---
set SCHEMA_DIR=%~dp0db_backups\schema
if not exist "%SCHEMA_DIR%" mkdir "%SCHEMA_DIR%"

echo Exporting bot_reporting schema (fixed name)...
pg_dump -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d bot_reporting --schema-only --no-owner --no-privileges -f "%SCHEMA_DIR%\bot_reporting_schema.sql"
if %errorlevel% neq 0 goto :error

echo Exporting dev_memory schema (fixed name)...
pg_dump -h %DB_HOST% -p %DB_PORT% -U %DB_USER% -d dev_memory --schema-only --no-owner --no-privileges -f "%SCHEMA_DIR%\dev_memory_schema.sql"
if %errorlevel% neq 0 goto :error

set PGPASSWORD=
echo Backup complete!
exit /b 0

:error
set PGPASSWORD=
echo Backup FAILED.
exit /b 1