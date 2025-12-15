-- GET_REPORT Procedure
-- See README.md for full documentation
CREATE OR REPLACE PROCEDURE GET_REPORT (
    p_report_id      IN NUMBER DEFAULT 1,
    p_settings_id    IN NUMBER DEFAULT 1,
    p_param_value    IN VARCHAR2 DEFAULT NULL
) IS
    v_blob BLOB;
    v_file_name VARCHAR2(200);
    v_hostname VARCHAR2(100);
    v_port VARCHAR2(5);
    v_username VARCHAR2(50);
    v_password VARCHAR2(50);
    v_base_report_path VARCHAR2(200);
    v_content_disposition VARCHAR2(50);
    v_param_names VARCHAR2(500);
    v_param_values VARCHAR2(500);
    v_report_url VARCHAR2(1000);
    v_param_names_tab apex_application_global.vc_arr2;
    v_param_values_tab apex_application_global.vc_arr2;
BEGIN
    SELECT HOSTNAME, PORT, USERNAME, PASSWORD, BASE_REPORT_PATH, CONTENT_DISPOSITION
    INTO v_hostname, v_port, v_username, v_password, v_base_report_path, v_content_disposition
    FROM MEDICAL_CENTER_SYSTEM.MANG_SYS_SEC_REPORT_SETTINGS
    WHERE ID = p_settings_id;

    SELECT FILE_NAME, PARAMETER_NAME, PARAMETER_VALUE
    INTO v_file_name, v_param_names, v_param_values
    FROM MEDICAL_CENTER_SYSTEM.MANG_SYS_SEC_REPORT_CONFIG
    WHERE ID = p_report_id;

    IF v_base_report_path IS NULL THEN
        v_base_report_path := '/';
    ELSIF NOT v_base_report_path LIKE '/%' THEN
        v_base_report_path := '/' || v_base_report_path;
    END IF;

    IF NOT v_base_report_path LIKE '%/' THEN
        v_base_report_path := v_base_report_path || '/';
    END IF;

    IF v_param_names IS NOT NULL THEN
        v_param_names_tab := apex_util.string_to_table(v_param_names, ';');
    END IF;

    IF p_param_value IS NOT NULL THEN
        v_param_values_tab := apex_util.string_to_table(p_param_value, ';');
    ELSIF v_param_values IS NOT NULL THEN
        v_param_values_tab := apex_util.string_to_table(v_param_values, ';');
    END IF;

    v_file_name := v_file_name || '.pdf';

    IF v_port = '443' OR v_port IS NULL THEN
        v_report_url := 'https://' || v_hostname || '/jasperserver/rest_v2/reports' || v_base_report_path || v_file_name;
    ELSE
        v_report_url := 'https://' || v_hostname || ':' || v_port || '/jasperserver/rest_v2/reports' || v_base_report_path || v_file_name;
    END IF;

    v_blob := apex_web_service.make_rest_request_b(
        p_url => v_report_url,
        p_http_method => 'GET',
        p_username => v_username,
        p_password => v_password,
        p_parm_name => v_param_names_tab,
        p_parm_value => v_param_values_tab
    );

    IF v_blob IS NOT NULL AND DBMS_LOB.GETLENGTH(v_blob) > 100 THEN
        OWA_UTIL.MIME_HEADER('application/pdf', FALSE);
        HTP.p('Content-Length: ' || DBMS_LOB.GETLENGTH(v_blob));
        HTP.p('Content-Disposition: ' || v_content_disposition || '; filename="' || v_file_name || '"');
        OWA_UTIL.http_header_close;
        WPG_DOCLOAD.DOWNLOAD_FILE(v_blob);
        APEX_APPLICATION.STOP_APEX_ENGINE;
    ELSE
        HTP.p('Error: Empty PDF');
    END IF;
END GET_REPORT;
