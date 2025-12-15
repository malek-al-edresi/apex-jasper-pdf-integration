# Oracle APEX – JasperReports PDF Integration

## 📌 Overview
This project provides a secure and dynamic integration between Oracle APEX and JasperReports Server for generating and downloading PDF reports via REST API.

The solution is implemented as a PL/SQL stored procedure that:
- Dynamically builds JasperReports REST URLs
- Supports configurable report paths and parameters
- Retrieves reports as BLOBs
- Streams PDFs directly to the browser from Oracle APEX

This approach is production-ready and suitable for Autonomous Database (ADB) and on-prem Oracle environments.

## 🧩 Key Features
- ✅ Dynamic JasperReports REST integration
- ✅ Parameterized reports (runtime override supported)
- ✅ Centralized server & report configuration (database-driven)
- ✅ Secure authentication (Basic Auth)
- ✅ Native PDF streaming to browser
- ✅ Oracle APEX compatible (ORDS)
- ✅ Error handling and diagnostics

## 🏗 Architecture
Oracle APEX  
↓  
APEX_WEB_SERVICE  
↓  
JasperReports REST API  
↓  
PDF (BLOB) → Browser Download

## 🗄 Database Objects

### 1️⃣ Report Settings Table
```sql
CREATE TABLE MANG_SYS_SEC_REPORT_SETTINGS (
    settings_id NUMBER PRIMARY KEY,
    jasper_server_url VARCHAR2(500),
    username VARCHAR2(100),
    password VARCHAR2(100),
    is_active CHAR(1) DEFAULT 'Y',
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE
);
```

### 2️⃣ Report Configuration Table
```sql
CREATE TABLE MANG_SYS_SEC_REPORT_CONFIG (
    report_id NUMBER PRIMARY KEY,
    settings_id NUMBER,
    report_path VARCHAR2(500),
    report_name VARCHAR2(200),
    default_params VARCHAR2(500),
    is_active CHAR(1) DEFAULT 'Y',
    created_date DATE DEFAULT SYSDATE,
    updated_date DATE DEFAULT SYSDATE,
    FOREIGN KEY (settings_id) REFERENCES MANG_SYS_SEC_REPORT_SETTINGS(settings_id)
);
```

## ⚙ Stored Procedure
```sql
CREATE OR REPLACE PROCEDURE GET_REPORT (
    p_report_id     IN NUMBER,
    p_settings_id   IN NUMBER DEFAULT NULL,
    p_param_value   IN VARCHAR2 DEFAULT NULL
) AS
    l_report_config MANG_SYS_SEC_REPORT_CONFIG%ROWTYPE;
    l_report_settings MANG_SYS_SEC_REPORT_SETTINGS%ROWTYPE;
    l_rest_url VARCHAR2(2000);
    l_report_params VARCHAR2(1000);
    l_username VARCHAR2(100);
    l_password VARCHAR2(100);
    l_base64_auth VARCHAR2(200);
    l_response CLOB;
    l_pdf_blob BLOB;
    l_http_status NUMBER;
    l_param_list APEX_T_VARCHAR2;
    l_query_string VARCHAR2(1000) := '';
    i PLS_INTEGER;
BEGIN
    -- Retrieve report configuration
    SELECT *
    INTO l_report_config
    FROM MANG_SYS_SEC_REPORT_CONFIG
    WHERE report_id = p_report_id
    AND is_active = 'Y';
    
    -- Determine settings ID to use
    DECLARE
        l_use_settings_id NUMBER := NVL(p_settings_id, l_report_config.settings_id);
    BEGIN
        SELECT *
        INTO l_report_settings
        FROM MANG_SYS_SEC_REPORT_SETTINGS
        WHERE settings_id = l_use_settings_id
        AND is_active = 'Y';
    END;
    
    -- Prepare report parameters
    IF p_param_value IS NOT NULL THEN
        l_report_params := p_param_value;
    ELSE
        l_report_params := l_report_config.default_params;
    END IF;
    
    -- Build query string if parameters exist
    IF l_report_params IS NOT NULL THEN
        l_param_list := APEX_STRING.SPLIT(l_report_params, ';');
        FOR i IN 1..l_param_list.COUNT LOOP
            IF i > 1 THEN
                l_query_string := l_query_string || '&';
            END IF;
            
            -- Handle parameter format (assuming format like "param1=value1" or just values)
            IF INSTR(l_param_list(i), '=') > 0 THEN
                l_query_string := l_query_string || l_param_list(i);
            ELSE
                -- If no equals sign, assume sequential parameters
                l_query_string := l_query_string || 'param' || i || '=' || l_param_list(i);
            END IF;
        END LOOP;
    END IF;
    
    -- Construct REST URL
    l_rest_url := l_report_settings.jasper_server_url || 
                  '/rest_v2/reports' || 
                  l_report_config.report_path || 
                  '.pdf';
                  
    IF l_query_string IS NOT NULL THEN
        l_rest_url := l_rest_url || '?' || l_query_string;
    END IF;
    
    -- Set authentication credentials
    l_username := l_report_settings.username;
    l_password := l_report_settings.password;
    
    -- Make REST call to JasperReports server
    APEX_WEB_SERVICE.G_REQUEST_HEADERS.DELETE;
    APEX_WEB_SERVICE.SET_REQUEST_HEADER('Content-Type', 'application/pdf');
    
    -- Add basic authentication header
    l_base64_auth := UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(UTL_RAW.CAST_TO_RAW(l_username || ':' || l_password)));
    APEX_WEB_SERVICE.SET_REQUEST_HEADER('Authorization', 'Basic ' || l_base64_auth);
    
    -- Call the JasperReports REST endpoint
    l_response := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
        p_url => l_rest_url,
        p_http_method => 'GET'
    );
    
    l_http_status := APEX_WEB_SERVICE.GET_LAST_HTTP_STATUS_CODE;
    
    IF l_http_status = 200 THEN
        -- Convert response to BLOB
        l_pdf_blob := APEX_WEB_SERVICE.GET_BLOB_RESPONSE;
        
        -- Stream PDF to browser
        OWA_UTIL.MIME_HEADER('application/pdf', FALSE);
        HTP.P('Content-Length: ' || DBMS_LOB.GETLENGTH(l_pdf_blob));
        HTP.P('Content-Disposition: attachment; filename="' || l_report_config.report_name || '.pdf"');
        OWA_UTIL.HTTP_HEADER_CLOSE;
        
        WPG_DOCLOAD.DOWNLOAD_FILE(l_pdf_blob);
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Error calling JasperReports server. HTTP Status: ' || l_http_status || '. URL: ' || l_rest_url);
    END IF;
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20002, 'Report configuration not found or inactive.');
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20003, 'Error in GET_REPORT procedure: ' || SQLERRM);
END GET_REPORT;
/
```

## ▶ Usage Example
```sql
BEGIN
  GET_REPORT(
    p_report_id   => 1,
    p_settings_id => 1,
    p_param_value => '1001;2025'
  );
END;
/
```

## 🔐 Security Considerations
- Store credentials securely in encrypted table columns
- Use Oracle Wallet for sensitive authentication data
- Implement proper access controls on the procedure
- Validate input parameters to prevent injection attacks

## 🛠 Troubleshooting
- Ensure JasperReports server is accessible from Oracle database
- Verify correct authentication credentials
- Check network connectivity between systems
- Review APEX_WEB_SERVICE package permissions

## 👤 Author
**Malek Mohammed Al-Edresi**  
Oracle APEX & Database Integration Specialist

