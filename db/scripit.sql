-- Professional Script for JasperReports Integration Tables and Procedure

-- Drop existing objects with proper error handling
DECLARE
    v_count NUMBER;
BEGIN
    -- Check and drop procedure
    BEGIN
        SELECT COUNT(*) 
        INTO v_count
        FROM USER_PROCEDURES 
        WHERE OBJECT_NAME = 'GET_REPORT';
        
        IF v_count > 0 THEN
            EXECUTE IMMEDIATE 'DROP PROCEDURE GET_REPORT';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -4043 THEN
                RAISE;
            END IF;
    END;

    -- Check and drop tables
    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM USER_TABLES
        WHERE TABLE_NAME = 'MANG_SYS_SEC_REPORT_CONFIG';
        
        IF v_count > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE MANG_SYS_SEC_REPORT_CONFIG CASCADE CONSTRAINTS';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -942 THEN
                RAISE;
            END IF;
    END;

    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM USER_TABLES
        WHERE TABLE_NAME = 'MANG_SYS_SEC_REPORT_SETTINGS';
        
        IF v_count > 0 THEN
            EXECUTE IMMEDIATE 'DROP TABLE MANG_SYS_SEC_REPORT_SETTINGS CASCADE CONSTRAINTS';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -942 THEN
                RAISE;
            END IF;
    END;
END;
/

-- Create sequence for primary keys
CREATE SEQUENCE mang_sys_sec_report_settings_seq START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE mang_sys_sec_report_config_seq START WITH 1 INCREMENT BY 1 NOCACHE;

-- Create table for report settings
CREATE TABLE MANG_SYS_SEC_REPORT_SETTINGS (
    settings_id     NUMBER PRIMARY KEY,
    jasper_server_url VARCHAR2(500),
    username        VARCHAR2(100),
    password        VARCHAR2(100),
    is_active       CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y', 'N')),
    created_date    DATE DEFAULT SYSDATE,
    updated_date    DATE DEFAULT SYSDATE
);

-- Create table for report configurations
CREATE TABLE MANG_SYS_SEC_REPORT_CONFIG (
    report_id       NUMBER PRIMARY KEY,
    settings_id     NUMBER NOT NULL,
    report_path     VARCHAR2(500),
    report_name     VARCHAR2(200),
    default_params  VARCHAR2(500),
    is_active       CHAR(1) DEFAULT 'Y' CHECK (is_active IN ('Y', 'N')),
    created_date    DATE DEFAULT SYSDATE,
    updated_date    DATE DEFAULT SYSDATE,
    CONSTRAINT fk_report_settings 
        FOREIGN KEY (settings_id) 
        REFERENCES MANG_SYS_SEC_REPORT_SETTINGS(settings_id)
);

-- Create indexes for performance
CREATE INDEX idx_report_config_settings ON MANG_SYS_SEC_REPORT_CONFIG(settings_id);
CREATE INDEX idx_report_config_active ON MANG_SYS_SEC_REPORT_CONFIG(is_active);
CREATE INDEX idx_report_settings_active ON MANG_SYS_SEC_REPORT_SETTINGS(is_active);

-- Create trigger to update timestamp
CREATE OR REPLACE TRIGGER tr_mang_sys_sec_report_settings_upd
    BEFORE UPDATE ON MANG_SYS_SEC_REPORT_SETTINGS
    FOR EACH ROW
BEGIN
    :NEW.updated_date := SYSDATE;
END;
/

CREATE OR REPLACE TRIGGER tr_mang_sys_sec_report_config_upd
    BEFORE UPDATE ON MANG_SYS_SEC_REPORT_CONFIG
    FOR EACH ROW
BEGIN
    :NEW.updated_date := SYSDATE;
END;
/

-- Create procedure to fetch reports
CREATE OR REPLACE PROCEDURE GET_REPORT (
    p_report_id      IN NUMBER,
    p_settings_id    IN NUMBER,
    p_param_value    IN VARCHAR2 DEFAULT NULL
) IS
    v_blob BLOB;
    v_file_name VARCHAR2(200);
    v_jasper_server_url VARCHAR2(500);
    v_username VARCHAR2(100);
    v_password VARCHAR2(100);
    v_report_path VARCHAR2(500);
    v_param_names_tab APEX_T_VARCHAR2;
    v_param_values_tab APEX_T_VARCHAR2;
    v_report_url VARCHAR2(2000);
    v_final_params VARCHAR2(1000);
    v_is_active CHAR(1);
    
    -- Exception declarations
    ex_invalid_report EXCEPTION;
    ex_invalid_settings EXCEPTION;
    ex_empty_response EXCEPTION;
    
BEGIN
    -- Validate input parameters
    IF p_report_id IS NULL OR p_settings_id IS NULL THEN
        RAISE_APPLICATION_ERROR(-20001, 'Report ID and Settings ID cannot be null');
    END IF;

    -- Get report configuration
    BEGIN
        SELECT report_path, report_name, default_params, is_active
        INTO v_report_path, v_file_name, v_final_params, v_is_active
        FROM MANG_SYS_SEC_REPORT_CONFIG
        WHERE report_id = p_report_id;
        
        IF v_is_active = 'N' THEN
            RAISE_APPLICATION_ERROR(-20002, 'Report configuration is inactive');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE ex_invalid_report;
    END;

    -- Get server settings
    BEGIN
        SELECT jasper_server_url, username, password, is_active
        INTO v_jasper_server_url, v_username, v_password, v_is_active
        FROM MANG_SYS_SEC_REPORT_SETTINGS
        WHERE settings_id = p_settings_id;
        
        IF v_is_active = 'N' THEN
            RAISE_APPLICATION_ERROR(-20003, 'Server settings are inactive');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE ex_invalid_settings;
    END;

    -- Process parameters
    IF p_param_value IS NOT NULL THEN
        v_param_values_tab := APEX_STRING.SPLIT(p_param_value, ';');
    ELSIF v_final_params IS NOT NULL THEN
        v_param_values_tab := APEX_STRING.SPLIT(v_final_params, ';');
    END IF;

    -- Construct report URL
    v_report_url := RTRIM(v_jasper_server_url, '/') || '/' || LTRIM(v_report_path, '/');
    
    -- Add file extension if missing
    IF SUBSTR(v_file_name, -4) != '.pdf' THEN
        v_file_name := v_file_name || '.pdf';
    END IF;

    -- Make REST request to JasperReports server
    v_blob := APEX_WEB_SERVICE.MAKE_REST_REQUEST_B(
        p_url => v_report_url,
        p_http_method => 'GET',
        p_username => v_username,
        p_password => v_password,
        p_transfer_timeout => 300
    );

    -- Validate response
    IF v_blob IS NULL OR DBMS_LOB.GETLENGTH(v_blob) < 100 THEN
        RAISE ex_empty_response;
    END IF;

    -- Set HTTP headers and return PDF
    OWA_UTIL.MIME_HEADER('application/pdf', FALSE);
    HTP.P('Content-Length: ' || DBMS_LOB.GETLENGTH(v_blob));
    HTP.P('Content-Disposition: inline; filename="' || v_file_name || '"');
    OWA_UTIL.HTTP_HEADER_CLOSE;
    WPG_DOCLOAD.DOWNLOAD_FILE(v_blob);
    APEX_APPLICATION.STOP_APEX_ENGINE;

EXCEPTION
    WHEN ex_invalid_report THEN
        HTP.P('Error: Invalid report ID specified');
    WHEN ex_invalid_settings THEN
        HTP.P('Error: Invalid server settings ID specified');
    WHEN ex_empty_response THEN
        HTP.P('Error: Received empty response from server');
    WHEN OTHERS THEN
        HTP.P('Error: ' || SQLERRM);
END GET_REPORT;
/

-- Grant execute permission
GRANT EXECUTE ON GET_REPORT TO PUBLIC;

-- Insert sample data (optional)
INSERT INTO MANG_SYS_SEC_REPORT_SETTINGS (
    settings_id, jasper_server_url, username, password, is_active
) VALUES (
    mang_sys_sec_report_settings_seq.NEXTVAL, 
    'https://your-jasper-server.com/jasperserver', 
    'admin', 
    'password', 
    'Y'
);

COMMIT;

-- Display creation summary
PROMPT ===============================================
PROMPT JasperReports Integration Objects Created Successfully
PROMPT ===============================================
PROMPT Tables Created:
PROMPT - MANG_SYS_SEC_REPORT_SETTINGS
PROMPT - MANG_SYS_SEC_REPORT_CONFIG
PROMPT 
PROMPT Sequence Created:
PROMPT - mang_sys_sec_report_settings_seq
PROMPT - mang_sys_sec_report_config_seq
PROMPT 
PROMPT Procedure Created:
PROMPT - GET_REPORT
PROMPT 
PROMPT Triggers Created:
PROMPT - tr_mang_sys_sec_report_settings_upd
PROMPT - tr_mang_sys_sec_report_config_upd
PROMPT ===============================================