DROP PROCEDURE IF EXISTS FindEmptyBed;
DELIMITER //

CREATE PROCEDURE FindEmptyBed(
    IN p_department_id INT, -- Đầu vào: Mã khoa cần tìm giường
    OUT p_bed_id INT        -- Đầu ra: Trả về Mã giường tìm được (hoặc NULL nếu hết)
)
BEGIN
    -- Khởi tạo giá trị mặc định là NULL trước khi tìm kiếm
    SET p_bed_id = NULL;

    -- Tìm 1 giường trống trong khoa và khóa dòng đó lại bằng (FOR UPDATE)
    SELECT bed_id INTO p_bed_id
    FROM Beds
    WHERE department_id = p_department_id AND patient_id IS NULL
    LIMIT 1
    FOR UPDATE;
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS ProcessEmergencyAdmission;
DELIMITER //

CREATE PROCEDURE ProcessEmergencyAdmission(
    IN p_patient_id INT,
    IN p_doctor_id INT,
    IN p_admission_time DATETIME,
    IN p_department_id INT,
    OUT p_status_message VARCHAR(255)
)
BEGIN
    -- Khai báo các biến cục bộ phục vụ kiểm tra điều kiện (Checkpoints)
    DECLARE v_is_admitted INT DEFAULT 0;
    DECLARE v_dept_exists INT DEFAULT 0;
    DECLARE v_assigned_bed_id INT; -- Biến dùng để "hứng" mã giường trả về từ Sub-Procedure

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_status_message = 'Lỗi hệ thống: Giao dịch đã bị hoàn tác an toàn.';
    END;

    -- [CHECKPOINT 1] Kiểm tra xem bệnh nhân đã có giường chưa
    SELECT COUNT(*) INTO v_is_admitted 
    FROM Beds 
    WHERE patient_id = p_patient_id;

    IF v_is_admitted > 0 THEN
        SET p_status_message = 'Từ chối: Bệnh nhân đang lưu trú';
    ELSE
        -- CHECKPOINT 2] Kiểm tra mã khoa truyền vào có tồn tại không
        SELECT COUNT(*) INTO v_dept_exists 
        FROM Departments 
        WHERE department_id = p_department_id;

        IF v_dept_exists = 0 THEN
            -- Chặn giao dịch nếu truyền sai mã khoa
            SET p_status_message = 'Từ chối: Khoa không tồn tại';
        ELSE
            -- MỐC KHỞI TẠO: Bắt đầu khối giao dịch thống nhất
            START TRANSACTION;

            -- Gọi Sub-Procedure để dò tìm giường trống. Truyền vào mã khoa và biến hứng kết quả
            CALL FindEmptyBed(p_department_id, v_assigned_bed_id);

            -- [CHECKPOINT 3] Xử lý kết quả trả về từ Sub-Procedure
            IF v_assigned_bed_id IS NULL THEN
                -- MỐC HOÀN TÁC: Nếu không tìm thấy giường -> Hủy bỏ giao dịch
                SET p_status_message = 'Từ chối: Khoa hiện đã hết giường';
                ROLLBACK;
            ELSE
                -- Nếu có giường trống -> Đi tiếp thực thi các lệnh cập nhật dữ liệu
                
                -- Bước 1: Tạo lịch khám mới
                INSERT INTO Appointments (patient_id, doctor_id, appointment_time, department_id)
                VALUES (p_patient_id, p_doctor_id, p_admission_time, p_department_id);

                -- Bước 2: Gán bệnh nhân vào giường vừa tìm được
                UPDATE Beds
                SET patient_id = p_patient_id
                WHERE bed_id = v_assigned_bed_id;

                -- MỐC XÁC NHẬN: Cả 2 thao tác thành công, lưu toàn bộ thay đổi vào Database
                SET p_status_message = 'Thành công: Đã tạo lịch khám và xếp giường';
                COMMIT;
            END IF;
        END IF;
    END IF;
END //
DELIMITER ;


CALL ProcessEmergencyAdmission(101, 5, '2026-05-12 08:30:00', 2, @result_1);
SELECT @result_1 AS Test_Case_1;

CALL ProcessEmergencyAdmission(102, 3, '2026-05-12 09:00:00', 1, @result_2);
SELECT @result_2 AS Test_Case_2;

CALL ProcessEmergencyAdmission(101, 4, '2026-05-12 10:15:00', 2, @result_3);
SELECT @result_3 AS Test_Case_3;

CALL ProcessEmergencyAdmission(105, 2, '2026-05-12 11:00:00', 999, @result_4);
SELECT @result_4 AS Test_Case_4;