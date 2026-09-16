USE spa_management;
GO

-- ====================================================================
-- I. Trigger & View
-- ====================================================================
-- 1. Kiểm tra tuổi khách hàng hợp lệ
CREATE OR ALTER TRIGGER tr_kiem_tra_tuoi_khach_hang
ON khach_hang
AFTER INSERT, UPDATE
AS
BEGIN
    -- Kiểm tra ngày sinh không được lớn hơn ngày hiện tại
    IF EXISTS (
        SELECT 1 FROM inserted 
        WHERE ngay_sinh IS NOT NULL 
        AND ngay_sinh > CAST(GETDATE() AS DATE)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(N'Ngày sinh không được lớn hơn ngày hiện tại!', 16, 1);
    END;

    -- Kiểm tra khách hàng phải từ 16 tuổi trở lên
    IF EXISTS (
        SELECT 1 FROM inserted 
        WHERE ngay_sinh IS NOT NULL 
        AND DATEDIFF(YEAR, ngay_sinh, GETDATE()) < 16
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(N'Khách hàng phải từ 16 tuổi trở lên!', 16, 1);
    END;
END;
GO

-- #2. Kiểm tra lịch hẹn hợp lệ
CREATE OR ALTER TRIGGER tr_kiem_tra_lich_hen
ON lich_hen
AFTER INSERT, UPDATE
AS
BEGIN
    -- Kiểm tra giờ làm việc (8:00 - 22:00)
    IF EXISTS (
        SELECT 1 FROM inserted 
        WHERE gio_bat_dau < '08:00' OR gio_ket_thuc > '22:00'
    )
    BEGIN
        ROLLBACK TRANSACTION;
		RAISERROR(N'Giờ bắt đầu và kết thúc phải nằm trong khung giờ làm việc (08:00 đến 22:00)', 16, 1);
    END;

	-- Không thể đặt lịch cho ngày trong quá khứ
    IF EXISTS (
        SELECT 1 FROM inserted 
        WHERE ngay_hen < CAST(GETDATE() AS DATE)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(N'Không thể đặt lịch cho ngày trong quá khứ!', 16, 1);
        RETURN;
    END;

    -- Không thể đặt lịch quá 30 ngày
    IF EXISTS (
        SELECT 1 FROM inserted 
        WHERE ngay_hen > DATEADD(DAY, 30, CAST(GETDATE() AS DATE))
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(N'Không thể đặt lịch quá 30 ngày!', 16, 1);
    END;
END;
GO
--3. Kiểm tra xung đột lịch phòng
CREATE OR ALTER TRIGGER tr_kiem_tra_xung_dot_phong
ON chi_tiet_lich_hen
AFTER INSERT, UPDATE
AS
BEGIN    
    -- Kiểm tra xung đột thời gian sử dụng phòng
    IF EXISTS (
        SELECT 1 
        FROM inserted i
        WHERE EXISTS (
            SELECT 1 
            FROM chi_tiet_lich_hen ctlh
            INNER JOIN lich_hen lh ON ctlh.ma_lich_hen = lh.ma_lich_hen
            WHERE ctlh.ma_phong = i.ma_phong
            AND ctlh.ma_ctlh != i.ma_ctlh
            AND lh.trang_thai NOT IN (N'hủy', N'không đến')
            AND (
                (i.thoi_gian_bat_dau < ctlh.thoi_gian_ket_thuc AND i.thoi_gian_ket_thuc > ctlh.thoi_gian_bat_dau)
            )
        )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(N'Phòng đã được đặt trong khung thời gian này!', 16, 1);
    END;
END;
GO

/**
-- Query kiểm tra trigger chi_tiet_lich_hen
INSERT INTO chi_tiet_lich_hen (ma_lich_hen, ma_dich_vu, ma_phong, thoi_gian_bat_dau, thoi_gian_ket_thuc)
VALUES 
(1, 1, 1, '2025-05-27 09:00', '2025-05-27 10:15'),
(2, 2, 2, '2025-05-28 11:00','2025-08-12 12:00');
**/

-- #4. Xử lý khi hóa đơn được thanh toán
CREATE OR ALTER TRIGGER tr_xu_ly_thanh_toan
ON hoa_don
AFTER INSERT, UPDATE
AS
BEGIN
   
    -- Chỉ xử lý khi trạng thái chuyển sang 'đã thanh toán'
    IF EXISTS (
        SELECT 1 
        FROM inserted i
        LEFT JOIN deleted d ON i.ma_hoa_don = d.ma_hoa_don
        WHERE i.trang_thai = N'đã thanh toán' 
        AND (d.ma_hoa_don IS NULL OR d.trang_thai != N'đã thanh toán')
    )
    BEGIN
        -- Cập nhật trạng thái lịch hẹn nếu có
        UPDATE lh
        SET 
            trang_thai = N'hoàn thành',
            ngay_cap_nhat = GETDATE()
        FROM lich_hen lh
        INNER JOIN inserted i ON lh.ma_lich_hen = i.ma_lich_hen
        WHERE i.trang_thai = N'đã thanh toán'
        AND lh.trang_thai NOT IN (N'hoàn thành', N'hủy');
        
        -- Cập nhật lịch sử sử dụng phòng
        UPDATE lssd
        SET 
            trang_thai = N'đã hoàn thành',
            thoi_gian_ket_thuc = GETDATE(),
            ngay_cap_nhat = GETDATE()
        FROM lich_su_su_dung_phong lssd
        INNER JOIN chi_tiet_lich_hen ctlh ON lssd.ma_ctlh = ctlh.ma_ctlh
        INNER JOIN inserted i ON ctlh.ma_lich_hen = i.ma_lich_hen
        WHERE i.trang_thai = N'đã thanh toán'
        AND lssd.trang_thai != N'đã hoàn thành';
    END;
END;
GO

-- 5. Cập nhật thông tin tổng hợp hóa đơn
CREATE OR ALTER TRIGGER trg_cap_nhat_thong_tin_hoa_don
ON chi_tiet_hoa_don
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Lấy danh sách hóa đơn bị ảnh hưởng
    DECLARE @hoa_don_anh_huong TABLE (ma_hoa_don INT);
    
    INSERT INTO @hoa_don_anh_huong(ma_hoa_don)
    SELECT DISTINCT ma_hoa_don FROM inserted
    UNION
    SELECT DISTINCT ma_hoa_don FROM deleted;
    
    -- Cập nhật thông tin tổng hợp
    UPDATE hd
    SET 
        tong_tien_goc = ISNULL(tong.tong_tien, 0),
        tong_so_dich_vu = ISNULL(tong.tong_so_luong, 0),
        tong_thoi_gian = ISNULL(tong.tong_thoi_gian, 0),
        tong_diem_tich_luy = ISNULL(tong.tong_diem, 0),
        gia_tri_diem = ISNULL(hd.diem_su_dung, 0) * 1000,
        ngay_cap_nhat = GETDATE()
    FROM hoa_don hd
    INNER JOIN @hoa_don_anh_huong hda ON hd.ma_hoa_don = hda.ma_hoa_don
    LEFT JOIN (
        SELECT 
            ma_hoa_don,
            SUM(thanh_tien) AS tong_tien,
            SUM(so_luong) AS tong_so_luong,
            SUM(tong_thoi_gian) AS tong_thoi_gian,
            SUM(tong_diem_tich_luy) AS tong_diem
        FROM chi_tiet_hoa_don
        WHERE ma_hoa_don IN (SELECT ma_hoa_don FROM @hoa_don_anh_huong)
        GROUP BY ma_hoa_don
    ) tong ON hd.ma_hoa_don = tong.ma_hoa_don;
END;
GO

-- 6. Cập nhật thông tin chi dịch vụ cho chi tiết hoá đơn
CREATE OR ALTER TRIGGER trg_cap_nhat_thong_tin_dich_vu_cthd
ON chi_tiet_hoa_don
AFTER INSERT, UPDATE
AS
BEGIN
    UPDATE cthd
    SET 
        cthd.gia_dv = dv.gia,
        cthd.thoi_gian_dv = dv.thoi_gian,
        cthd.diem_tich_luy_dv = dv.diem_tich_luy
    FROM chi_tiet_hoa_don cthd
    INNER JOIN inserted i ON cthd.ma_cthd = i.ma_cthd
    INNER JOIN dich_vu dv ON i.ma_dich_vu = dv.ma_dich_vu;
END;
GO


--
-- 7 view vw_DichVu_PhongHoatDong
CREATE or ALTER VIEW vw_DichVu_PhongHoatDong AS
SELECT 
    -- Thông tin dịch vụ
    dv.ma_dich_vu,
    dv.ten_dich_vu,
    dv.mo_ta AS mo_ta_dich_vu,
    dv.phan_loai AS phan_loai_dich_vu,
    dv.gia,
    dv.thoi_gian,
    dv.trang_thai AS trang_thai_dich_vu,
    pdv.ma_phong,
    pdv.ten_phong,
    pdv.loai_phong,
    pdv.suc_chua,
    pdv.trang_thai AS trang_thai_phong

FROM 
    dbo.dich_vu AS dv
INNER JOIN 
    dbo.phong_dich_vu AS pdv ON dv.ma_dich_vu = pdv.ma_dich_vu

WHERE 
    dv.trang_thai = N'hoạt động'
    AND pdv.trang_thai = N'hoạt động'
GO

-- 8. TOP 50 khách hàng vip vw_top_khach_hang_vip. tính theo tổng chi tiêu giảm dần
CREATE OR ALTER VIEW vw_top_khach_hang_vip AS
SELECT TOP 50
    kh.ma_khach_hang,
    kh.ho_ten,
    kh.so_dien_thoai,
    kh.cap_thanh_vien,
    COUNT(hd.ma_hoa_don) as so_lan_su_dung,
    SUM(hd.tong_thanh_toan) as tong_chi_tieu,
    AVG(hd.tong_thanh_toan) as chi_tieu_trung_binh,
    MAX(hd.ngay_xuat) as lan_den_gan_nhat,
    RANK() OVER (ORDER BY SUM(hd.tong_thanh_toan) DESC) as hang_chi_tieu
FROM khach_hang kh
INNER JOIN hoa_don hd ON kh.ma_khach_hang = hd.ma_khach_hang 
                      AND hd.trang_thai = N'đã thanh toán'
WHERE kh.trang_thai = N'hoạt động'
GROUP BY kh.ma_khach_hang, kh.ho_ten, kh.so_dien_thoai, kh.cap_thanh_vien
ORDER BY tong_chi_tieu DESC;
GO
-- ====================================================================
-- II. Store Procedure
-- ====================================================================
-- 1. PROCEDURE TẠO LỊCH HẸN  
/*
-- procedure sp_TaoLichHen thêm lịch hẹn dựa vào: vw_DichVu_PhongHoatDong
  Mô tả: Tạo lịch hẹn cho khách hàng sử dụng dịch vụ tại một phòng phù hợp.
    1. k.tra lấy thông tin khách hàng và dịch vụ hợp lệ (còn hoạt động)
	2. tính thời gian bắt đầu, kết thúc từ dữ liệu dịch vụ
	3. tìm phòng phù hợp với dịch vụ.
    5. kiểm tra có bị trùng lịch trong bảng chi_tiet_lich_hen và lich_su_su_dung_phong không?
    7. tạo và lưu lịch hẹn mới trong bảng lịch hẹn, chi tiết lịch hẹn, lịch sử sử dụng phòng
*/

DROP PROCEDURE IF EXISTS sp_TaoLichHen
GO
CREATE PROCEDURE sp_TaoLichHen
    @ma_khach_hang INT,
    @ma_dich_vu INT,
    @ngay_hen DATE,
    @gio_bat_dau TIME,
    @ghi_chu NVARCHAR(MAX) = NULL,
    @ma_lich_hen INT OUTPUT,
    @ket_qua NVARCHAR(255) OUTPUT
AS
BEGIN
    DECLARE 
        @gia INT, 
        @phut INT, 
        @ma_phong INT,
        @bat_dau DATETIME2, 
        @ket_thuc DATETIME2,
        @gio_ket_thuc TIME,
        @ma_ctlh INT;

    BEGIN TRY
        -- 1. Kiểm tra khách hàng
        IF NOT EXISTS (
            SELECT 1 FROM khach_hang 
            WHERE ma_khach_hang = @ma_khach_hang AND trang_thai = N'hoạt động'
        )
        BEGIN
            SET @ket_qua = N'Khách hàng không hợp lệ';
            RETURN;
        END

        -- 2. Lấy thông tin dịch vụ
		IF NOT EXISTS (
			SELECT 1 FROM dich_vu WHERE ma_dich_vu = @ma_dich_vu AND trang_thai = N'hoạt động'
		)
		BEGIN
			SET @ket_qua = N'Dịch vụ không hợp lệ hoặc không hoạt động';
			RETURN;
		END

		SELECT @gia = gia, @phut = thoi_gian
		FROM dich_vu
		WHERE ma_dich_vu = @ma_dich_vu;


        -- 3. Tính thời gian bắt đầu/kết thúc
        SET @bat_dau = DATEADD(SECOND, DATEDIFF(SECOND, 0, @gio_bat_dau), CAST(@ngay_hen AS DATETIME2));
        SET @ket_thuc = DATEADD(MINUTE, @phut, @bat_dau);
        SET @gio_ket_thuc = CAST(@ket_thuc AS TIME);

        -- 4. Tìm phòng phù hợp
		IF NOT EXISTS (
			SELECT 1
			FROM phong_dich_vu
			WHERE trang_thai = N'hoạt động'
			  AND ma_dich_vu = @ma_dich_vu
		)
		BEGIN
			SET @ket_qua = N'Không có phòng dịch vụ phù hợp với mã dịch vụ này';
			RETURN;
		END

		-- Nếu có, thì tìm phòng khớp dịch vụ 
		SELECT TOP 1 @ma_phong = ma_phong
		FROM phong_dich_vu
		WHERE trang_thai = N'hoạt động'
		  AND (ma_dich_vu = @ma_dich_vu OR ma_dich_vu IS NULL)
		ORDER BY CASE WHEN ma_dich_vu = @ma_dich_vu THEN 0 ELSE 1 END;

        -- 5. Kiểm tra trùng lịch hẹn trong chi_tiet_lich_hen
        IF EXISTS (
            SELECT 1
            FROM chi_tiet_lich_hen ctlh
            INNER JOIN lich_hen lh ON ctlh.ma_lich_hen = lh.ma_lich_hen
            WHERE ctlh.ma_phong = @ma_phong
              AND lh.ngay_hen = @ngay_hen
              AND lh.trang_thai IN (N'đặt', N'xác nhận', N'đang thực hiện')
              AND (
                  @bat_dau < ctlh.thoi_gian_ket_thuc
                  AND @ket_thuc > ctlh.thoi_gian_bat_dau
              )
        )
        BEGIN
            SET @ket_qua = N'Phòng đã có lịch hẹn trong khoảng thời gian này';
            RETURN;
        END

        -- 6. Kiểm tra trùng lịch sử sử dụng phòng
        IF EXISTS (
            SELECT 1
            FROM lich_su_su_dung_phong
            WHERE ma_phong = @ma_phong
              AND (
                  @bat_dau < thoi_gian_ket_thuc
                  AND @ket_thuc > thoi_gian_bat_dau
              )
              AND trang_thai IN (N'đặt lịch', N'đang sử dụng')
        )
        BEGIN
            SET @ket_qua = N'Trong khung giờ này phòng đã có lịch sử sử dụng';
            RETURN;
        END

        -- 7. Bắt đầu tạo lịch hẹn
        BEGIN TRANSACTION;

        INSERT INTO lich_hen (ma_khach_hang, ngay_hen, gio_bat_dau, gio_ket_thuc, tong_tien, ghi_chu)
        VALUES (@ma_khach_hang, @ngay_hen, @gio_bat_dau, @gio_ket_thuc, @gia, @ghi_chu);

        SET @ma_lich_hen = SCOPE_IDENTITY();

        -- 8. Tạo chi tiết lịch hẹn
        INSERT INTO chi_tiet_lich_hen (ma_lich_hen, ma_dich_vu, ma_phong, thoi_gian_bat_dau, thoi_gian_ket_thuc)
        VALUES (@ma_lich_hen, @ma_dich_vu, @ma_phong, @bat_dau, @ket_thuc);

        SET @ma_ctlh = SCOPE_IDENTITY();

        -- 9. Tạo lịch sử sử dụng phòng
        INSERT INTO lich_su_su_dung_phong (
            ma_phong, ma_ctlh, thoi_gian_bat_dau, thoi_gian_ket_thuc, trang_thai
        )
        VALUES (
            @ma_phong, @ma_ctlh, @bat_dau, @ket_thuc, N'đặt lịch'
        );

        SET @ket_qua = N'Tạo lịch hẹn thành công';

		-- in ra thông tin
		SELECT 
			lh.ma_lich_hen,
			lh.ma_khach_hang,
			lh.ngay_hen,
			lh.gio_bat_dau,
			lh.gio_ket_thuc,
			ctlh.ma_dich_vu,
			ctlh.ma_phong,
			lh.tong_tien,
			lh.trang_thai AS trang_thai_lich_hen,
			lh.ghi_chu,
			lssdp.thoi_gian_bat_dau,
			lssdp.thoi_gian_ket_thuc,
			lssdp.trang_thai AS trang_thai_su_dung
		FROM lich_hen AS lh
		JOIN chi_tiet_lich_hen AS ctlh 
			ON lh.ma_lich_hen = ctlh.ma_lich_hen
		JOIN lich_su_su_dung_phong AS lssdp 
			ON ctlh.ma_ctlh = lssdp.ma_ctlh
		WHERE lh.ma_lich_hen = @ma_lich_hen

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @ket_qua = N'Lỗi: ' + ERROR_MESSAGE();
        SET @ma_lich_hen = NULL;
    END CATCH
END;
GO
/**

--Query kiểm tra them_dich_vu 
--select * from vw_DichVu_PhongHoatDong

-- Lần 1: Thêm ma_dich_vu ngừng phục vụ (vd: mã 20) -> Failed
DECLARE @ma_lich_hen INT, @ket_qua NVARCHAR(255);

EXEC sp_TaoLichHen
    @ma_khach_hang = 1,
    @ma_dich_vu = 20,
    @ngay_hen = '2025-06-12',
    @gio_bat_dau = '09:00:00',
    @ghi_chu = N'Khách VIP',
    @ma_lich_hen = @ma_lich_hen OUTPUT,
    @ket_qua = @ket_qua OUTPUT;
SELECT @ma_lich_hen AS MaLichHen, @ket_qua AS KetQua;
GO
-- Lần 2: thêm dịch vụ với mã khách hàng không tồn tại. vd: 100  -> Failed
DECLARE @ma_lich_hen INT, @ket_qua NVARCHAR(255);

EXEC sp_TaoLichHen
    @ma_khach_hang = 100,
    @ma_dich_vu = 14,
    @ngay_hen = '2025-06-12',
    @gio_bat_dau = '09:00:00',
    @ghi_chu = N'Khách VIP',
    @ma_lich_hen = @ma_lich_hen OUTPUT,
    @ket_qua = @ket_qua OUTPUT;
SELECT @ma_lich_hen AS MaLichHen, @ket_qua AS KetQua;
GO
-- Lần 3: Thêm lịch ưu tiên lúc 10:00 
DECLARE @ma_lich_hen INT, @ket_qua NVARCHAR(255);

EXEC sp_TaoLichHen
    @ma_khach_hang = 1,
    @ma_dich_vu = 14,
    @ngay_hen = '2025-06-02',
    @gio_bat_dau = '10:00:00',
    @ghi_chu = N'Lịch ưu tiên',
    @ma_lich_hen = @ma_lich_hen OUTPUT,
    @ket_qua = @ket_qua OUTPUT;

SELECT @ma_lich_hen AS MaLichHen, @ket_qua AS KetQua;

GO

-- Lần 4: Thử tạo trùng giờ với lần 3 -> Failed
DECLARE @ma_lich_hen INT, @ket_qua NVARCHAR(255);

EXEC sp_TaoLichHen
    @ma_khach_hang = 1,
    @ma_dich_vu = 14,
    @ngay_hen = '2025-06-02',
    @gio_bat_dau = '09:00:00',
    @ghi_chu = N'Trùng giờ với lịch trước',
    @ma_lich_hen = @ma_lich_hen OUTPUT,
    @ket_qua = @ket_qua OUTPUT;


**/
-- ====================================================================
-- 2. PROCEDURE TẠO HÓA ĐƠN TỪ LỊCH HẸN
-- ====================================================================
GO
CREATE OR ALTER PROCEDURE sp_tao_hoa_don_tu_lich_hen
    @ma_lich_hen INT,
    @ma_nhan_vien INT,
    @phuong_thuc NVARCHAR(20) = NULL,  
	@ma_hoa_don INT OUTPUT
AS
BEGIN

    -- 1. Kiểm tra lịch hẹn hợp lệ
    IF NOT EXISTS (
        SELECT 1 FROM lich_hen 
        WHERE ma_lich_hen = @ma_lich_hen AND trang_thai != 'hoàn thành'
    )
    BEGIN
        RAISERROR(N'Lịch hẹn không tồn tại hoặc không ở trạng thái "đang thực hiện"', 16, 1);
        RETURN;
    END;

    DECLARE 
        @ma_khach_hang INT,
        @ngay_hen DATE;

    SELECT 
        @ma_khach_hang = ma_khach_hang,
        @ngay_hen = ngay_hen
    FROM lich_hen
    WHERE ma_lich_hen = @ma_lich_hen;

    -- 2. Kiểm tra đã có hóa đơn chưa
    IF EXISTS (
        SELECT 1 FROM hoa_don WHERE ma_lich_hen = @ma_lich_hen
    )
    BEGIN
        RAISERROR(N'Lịch hẹn này đã có hóa đơn!', 16, 1);
        RETURN;
    END;

    -- 3. Tạo hóa đơn mới (cho phép phương thức thanh toán NULL)
    INSERT INTO hoa_don (
        ma_khach_hang, ma_nhan_vien, ma_lich_hen,
        ngay_xuat, phuong_thuc, trang_thai, ngay_cap_nhat
    )
    VALUES (
        @ma_khach_hang, @ma_nhan_vien, @ma_lich_hen,
        GETDATE(), @phuong_thuc, N'chờ thanh toán', GETDATE()
    );

    SET @ma_hoa_don = SCOPE_IDENTITY();

    -- 4. Tạo chi tiết hóa đơn từ chi tiết lịch hẹn
    INSERT INTO chi_tiet_hoa_don (
        ma_hoa_don, ma_dich_vu, ma_nhan_vien, so_luong
    )
    SELECT 
        @ma_hoa_don,
        ctlh.ma_dich_vu,
        @ma_nhan_vien,
        1
    FROM chi_tiet_lich_hen ctlh
    WHERE ctlh.ma_lich_hen = @ma_lich_hen;

    -- 5. Tạo lịch sử sử dụng phòng từ chi tiết lịch hẹn
    INSERT INTO lich_su_su_dung_phong (
        ma_phong, ma_ctlh, thoi_gian_bat_dau, thoi_gian_ket_thuc, trang_thai, ngay_cap_nhat
    )
    SELECT 
        ctlh.ma_phong,
        ctlh.ma_ctlh,
        ctlh.thoi_gian_bat_dau,
        ctlh.thoi_gian_ket_thuc,
        N'đang sử dụng',
        GETDATE()
    FROM chi_tiet_lich_hen ctlh
    WHERE ctlh.ma_lich_hen = @ma_lich_hen;

	SELECT *
	FROM hoa_don
	WHERE ma_hoa_don = @ma_hoa_don

    PRINT N'Đã tạo hóa đơn thành công. Phương thức thanh toán có thể cập nhật sau.';
END;
GO

-- Procedure tạo hoá đơn từ lịch hẹn trước đó
--DECLARE @ma_hoa_don INT;
--EXEC sp_tao_hoa_don_tu_lich_hen 
--    @ma_lich_hen   = 11,
--    @ma_nhan_vien  = 10,
--    @phuong_thuc   = N'Tiền mặt',
--    @ma_hoa_don    = @ma_hoa_don OUTPUT;

--PRINT N'Mã hóa đơn vừa tạo:';
--SELECT @ma_hoa_don AS [Mã hóa đơn];
--GO

--DECLARE @ma_hoa_don INT;
--EXEC sp_tao_hoa_don_tu_lich_hen 
--    @ma_lich_hen   = 12,
--    @ma_nhan_vien  = 10,
--    @phuong_thuc   = N'Tiền mặt',
--    @ma_hoa_don    = @ma_hoa_don OUTPUT;

--PRINT N'Mã hóa đơn vừa tạo:';
--SELECT @ma_hoa_don AS [Mã hóa đơn];

-- ====================================================================
-- 3. Procedure sp_tao_hoa_don và sp_tao_chi_tiet_hoa_don khi không cần lịch hẹn
-- ====================================================================
/*
3.1. Procedure sp_tao_hoa_don
 - tao hoa don moi neu ma lich hen null
*/
GO
DROP PROCEDURE IF EXISTS sp_tao_hoa_don;
GO

CREATE PROCEDURE sp_tao_hoa_don
    @ma_khach_hang INT,
    @ma_nhan_vien INT,
    @ma_uu_dai INT = NULL,
    @ma_lich_hen INT = NULL,
    @phuong_thuc NVARCHAR(20),
    @ma_hoa_don_moi INT OUTPUT
AS
BEGIN
    INSERT INTO hoa_don (
        ma_khach_hang, ma_nhan_vien, ma_uu_dai, ma_lich_hen,
        phuong_thuc, ngay_tao, ngay_cap_nhat
    )
    VALUES (
        @ma_khach_hang, @ma_nhan_vien, @ma_uu_dai, @ma_lich_hen,
        @phuong_thuc, GETDATE(), GETDATE()
    );

    SET @ma_hoa_don_moi = SCOPE_IDENTITY();

    SELECT *
    FROM hoa_don
    WHERE ma_hoa_don = @ma_hoa_don_moi;
END;
GO

/*
3.2. Procedure sp_tao_chi_tiet_hoa_don
 - ktra mã dịch vụ tồn tại
 - tự động cập nhật dịch vụ chi tiết hoá đơn nhờ trigger [trg_cap_nhat_thong_tin_dich_vu_cthd]
 - trả kết quả & thông báo thành công/lỗi.
*/
DROP PROCEDURE IF EXISTS sp_tao_chi_tiet_hoa_don;
GO

CREATE PROCEDURE sp_tao_chi_tiet_hoa_don
    @ma_hoa_don     INT,
    @ma_dich_vu     INT,
    @ma_nhan_vien   INT,
    @so_luong       INT,
    @ghi_chu        NVARCHAR(300) = NULL,
    @ma_cthd        INT OUTPUT,
    @ket_qua        NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
		-- Kiểm tra xem mã dịch vụ có tồn tại không
        IF NOT EXISTS (
            SELECT 1 FROM dich_vu WHERE ma_dich_vu = @ma_dich_vu
        )
        BEGIN
            SET @ket_qua = N'Lỗi: Mã dịch vụ ' + CAST(@ma_dich_vu AS NVARCHAR) + N' không tồn tại.';
            PRINT @ket_qua;
            RETURN;
        END

        -- Thêm chi tiết hoá đơn
        INSERT INTO chi_tiet_hoa_don (
            ma_hoa_don, ma_dich_vu, ma_nhan_vien,
            so_luong, ghi_chu
        )
        VALUES (
            @ma_hoa_don, @ma_dich_vu, @ma_nhan_vien,
            @so_luong, @ghi_chu
        );

        SET @ma_cthd = SCOPE_IDENTITY();
        SET @ket_qua = N'Thêm chi tiết hoá đơn thành công (ma_cthd = ' + CAST(@ma_cthd AS NVARCHAR) + N')';

        PRINT @ket_qua;

        -- Trả dữ liệu sau khi in kết quả
        SELECT * 
        FROM chi_tiet_hoa_don
        WHERE ma_cthd = @ma_cthd;
    END TRY

    BEGIN CATCH
        SET @ket_qua = N'Lỗi: ' + ERROR_MESSAGE();
        PRINT @ket_qua;
    END CATCH
END;
GO
/**
Test trigger: 
-- insert mã dịch vụ cho hoa đơn 15 với dịch vụ 6
DECLARE @ma_cthd INT, 
        @ket_qua NVARCHAR(255);

EXEC sp_tao_chi_tiet_hoa_don 
    @ma_hoa_don    = 15,
    @ma_dich_vu    = 6,
    @ma_nhan_vien  = 2,
    @so_luong      = 1,
    @ghi_chu       = N'Làm sạch, tẩy tế bào chết, đắp mặt nạ dưỡng ẩm',
    @ma_cthd       = @ma_cthd OUTPUT,
    @ket_qua       = @ket_qua OUTPUT;

-- insert mã dịch vụ cho hoa đơn 15 với dịch vụ 4
DECLARE @ma_cthd2 INT,
        @ket_qua2 NVARCHAR(255);

EXEC sp_tao_chi_tiet_hoa_don 
    @ma_hoa_don    = 15,
    @ma_dich_vu    = 4,
    @ma_nhan_vien  = 3,
    @so_luong      = 1,
    @ghi_chu       = N'Massage toàn thân giúp thư giãn cơ bắp, giảm căng thẳng',
    @ma_cthd       = @ma_cthd2 OUTPUT,
    @ket_qua       = @ket_qua2 OUTPUT;
go
-- Gọi lần 3 -> insert dữ liệu với dữ liệu gọi lần 2 để trả về failed
DECLARE @ma_cthd3 INT,
        @ket_qua3 NVARCHAR(255);

EXEC sp_tao_chi_tiet_hoa_don 
    @ma_hoa_don    = 15,
    @ma_dich_vu    = 4,
    @ma_nhan_vien  = 3,
    @so_luong      = 1,
    @ghi_chu       = N'Massage toàn thân giúp thư giãn cơ bắp, giảm căng thẳng',
    @ma_cthd       = @ma_cthd3 OUTPUT,
    @ket_qua       = @ket_qua3 OUTPUT;
select @ket_qua3

**/

-- ====================================================================
-- III. Phân Quyền
-- ====================================================================
-- 3.1 Tạo phân quyền
-- 1. Tạo login trong master
USE master;
GO

IF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = 'quan_ly_login')
    CREATE LOGIN quan_ly_login WITH PASSWORD = '123';

IF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = 'nhan_vien_login')
    CREATE LOGIN nhan_vien_login WITH PASSWORD = '123';

IF NOT EXISTS (SELECT * FROM sys.sql_logins WHERE name = 'khach_hang_login')
    CREATE LOGIN khach_hang_login WITH PASSWORD = '123';
GO

-- 2. Thiết lập DB spa_management
USE spa_management;
GO

-- 3. TẠO ROLE
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'quan_ly')
    CREATE ROLE quan_ly;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'nhan_vien')
    CREATE ROLE nhan_vien;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'khach_hang')
    CREATE ROLE khach_hang;
GO


-- 4: Tạo User nếu chưa có
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'user_quan_ly')
    CREATE USER user_quan_ly FOR LOGIN quan_ly_login;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'user_nhan_vien')
    CREATE USER user_nhan_vien FOR LOGIN nhan_vien_login;

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'user_khach_hang')
    CREATE USER user_khach_hang FOR LOGIN khach_hang_login;
GO

-- 5: GÁN USER VÀO ROLE (CHỈ KHI USER TỒN TẠI)
IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'user_quan_ly')
    ALTER ROLE quan_ly ADD MEMBER user_quan_ly;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'user_nhan_vien')
    ALTER ROLE nhan_vien ADD MEMBER user_nhan_vien;

IF EXISTS (SELECT * FROM sys.database_principals WHERE name = 'user_khach_hang')
    ALTER ROLE khach_hang ADD MEMBER user_khach_hang;
GO

-- 6: Cấp quyền Connect
GRANT CONNECT TO user_quan_ly;
GRANT CONNECT TO user_nhan_vien;
GRANT CONNECT TO user_khach_hang;
GO

-- 7: Phân quyền cho từng roles cụ thể

-- QUYỀN CHO quan_ly
GRANT SELECT, INSERT, UPDATE, DELETE ON khach_hang TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON dich_vu TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON nhan_vien TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON phong_dich_vu TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON chuong_trinh_uu_dai TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON lich_hen TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON chi_tiet_lich_hen TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON hoa_don TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON chi_tiet_hoa_don TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON lich_su_su_dung_phong TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON diem_tich_luy TO quan_ly;
GRANT SELECT, INSERT, UPDATE, DELETE ON danh_gia_dich_vu TO quan_ly;

-- QUYỀN CHO nhan_vien
GRANT SELECT ON khach_hang TO nhan_vien;
GRANT SELECT ON dich_vu TO nhan_vien;
GRANT SELECT ON nhan_vien TO nhan_vien;
GRANT SELECT ON phong_dich_vu TO nhan_vien;
GRANT SELECT ON chuong_trinh_uu_dai TO nhan_vien;
GRANT SELECT ON lich_hen TO nhan_vien;
GRANT SELECT ON chi_tiet_lich_hen TO nhan_vien;
GRANT SELECT ON hoa_don TO nhan_vien;
GRANT SELECT ON chi_tiet_hoa_don TO nhan_vien;
GRANT SELECT ON lich_su_su_dung_phong TO nhan_vien;
GRANT SELECT ON diem_tich_luy TO nhan_vien;
GRANT SELECT ON danh_gia_dich_vu TO nhan_vien;

GRANT INSERT, UPDATE ON khach_hang TO nhan_vien;
GRANT INSERT, UPDATE ON lich_hen TO nhan_vien;
GRANT INSERT, UPDATE ON chi_tiet_lich_hen TO nhan_vien;
GRANT INSERT, UPDATE ON hoa_don TO nhan_vien;
GRANT INSERT, UPDATE ON chi_tiet_hoa_don TO nhan_vien;
GRANT INSERT, UPDATE ON lich_su_su_dung_phong TO nhan_vien;
GRANT INSERT, UPDATE ON diem_tich_luy TO nhan_vien;

-- QUYỀN CHO khach_hang
GRANT SELECT ON dich_vu TO khach_hang;
GRANT SELECT ON chuong_trinh_uu_dai TO khach_hang;
GRANT SELECT ON lich_hen TO khach_hang;
GRANT SELECT ON hoa_don TO khach_hang;
GRANT SELECT ON chi_tiet_hoa_don TO khach_hang;
GRANT SELECT ON diem_tich_luy TO khach_hang;
GRANT SELECT ON danh_gia_dich_vu TO khach_hang;

GRANT INSERT, UPDATE ON khach_hang TO khach_hang;
GRANT INSERT, UPDATE ON danh_gia_dich_vu TO khach_hang;
GRANT INSERT, UPDATE ON lich_hen TO khach_hang;
GO

-- ROLE: quan_ly: Toàn quyền thao tác tất cả procedure
GRANT EXECUTE ON sp_TaoLichHen TO quan_ly;
GRANT EXECUTE ON sp_tao_hoa_don_tu_lich_hen TO quan_ly;
GRANT EXECUTE ON sp_tao_hoa_don TO quan_ly;
GRANT EXECUTE ON sp_tao_chi_tiet_hoa_don TO quan_ly;

-- ROLE: nhan_vien: Chỉ được tạo lịch hẹn & chi tiết hóa đơn (không được tạo hóa đơn tổng)
GRANT EXECUTE ON sp_TaoLichHen TO nhan_vien;
GRANT EXECUTE ON sp_tao_chi_tiet_hoa_don TO nhan_vien;

-- ROLE: khach_hang :
GRANT EXECUTE ON sp_TaoLichHen TO khach_hang;


-- 3.2 Kiểm tra phân quyền

BEGIN TRANSACTION;

PRINT N'Tên đăng nhập hệ thống: ' + SYSTEM_USER + N' Tên người dùng cơ sở dữ liệu: ' + SYSTEM_USER

-- Check DELETE 
PRINT N'Kiểm tra quyền DELETE trên bảng [hoa_don]'
BEGIN TRY
    DELETE FROM [dbo].[hoa_don] WHERE 1 = 0
    PRINT N'Thành công: Có quyền DELETE trên bảng [hoa_don]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền DELETE trên bảng [hoa_don]';
    PRINT ERROR_MESSAGE();
END CATCH;

PRINT N'Kiểm tra quyền DELETE trên bảng [chi_tiet_hoa_don]'
BEGIN TRY
    DELETE FROM [dbo].[chi_tiet_hoa_don] WHERE 1 = 0
    PRINT N'Thành công: Có quyền DELETE trên bảng [chi_tiet_hoa_don]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền DELETE trên bảng [chi_tiet_hoa_don]';
    PRINT ERROR_MESSAGE();
END CATCH;

-- Check UPDATE 
PRINT N'Kiểm tra quyền UPDATE trên bảng [lich_hen]'
BEGIN TRY
    UPDATE [dbo].[lich_hen]
    SET ghi_chu = N'Ghi chú kiểm tra'
    WHERE 1 = 0
    PRINT N'Thành công: Có quyền UPDATE trên bảng [lich_hen]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền UPDATE trên bảng [lich_hen]';
    PRINT ERROR_MESSAGE();
END CATCH;

PRINT N'Kiểm tra quyền UPDATE trên bảng [nhan_vien]'
BEGIN TRY
    UPDATE [dbo].[nhan_vien]
    SET ho_ten = ho_ten
    WHERE 1 = 0
    PRINT N'Thành công: Có quyền UPDATE trên bảng [nhan_vien]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền UPDATE trên bảng [nhan_vien]';
    PRINT ERROR_MESSAGE();
END CATCH;

-- Check quyền SELECT 
PRINT N'Kiểm tra quyền SELECT trên bảng [khach_hang]'
BEGIN TRY
    SELECT TOP 1 * FROM [dbo].[khach_hang]
    PRINT N'Thành công: Có quyền SELECT trên bảng [khach_hang]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền SELECT trên bảng [khach_hang]';
    PRINT ERROR_MESSAGE();
END CATCH;

PRINT N'Kiểm tra quyền SELECT trên bảng [dich_vu]'
BEGIN TRY
    SELECT TOP 1 * FROM [dbo].[dich_vu]
    PRINT N'Thành công: Có quyền SELECT trên bảng [dich_vu]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền SELECT trên bảng [dich_vu]';
    PRINT ERROR_MESSAGE();
END CATCH;

-- Check INSERT 
PRINT N'Kiểm tra quyền INSERT trên bảng [dich_vu]'
BEGIN TRY
    INSERT INTO [dbo].[dich_vu](ten_dich_vu, mo_ta, phan_loai, gia, thoi_gian)
    VALUES (N'Spa', N'Spa chuyên môn', N'massage', 100000, 60)
    PRINT N'Thành công: Có quyền INSERT trên bảng [dich_vu]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền INSERT trên bảng [dich_vu]';
    PRINT ERROR_MESSAGE();
END CATCH;

PRINT N'Kiểm tra quyền INSERT trên bảng [nhan_vien]'
BEGIN TRY
    INSERT INTO [dbo].[nhan_vien](ho_ten, so_dien_thoai, chuyen_mon, mat_khau)
    VALUES (N'Nguyễn Thị Yến', '0123456789', N'Chăm sóc khách hàng', 0x010203)
    PRINT N'Thành công: Có quyền INSERT trên bảng [nhan_vien]';
END TRY
BEGIN CATCH
    PRINT N'Lỗi: Không có quyền INSERT trên bảng [nhan_vien]';
    PRINT ERROR_MESSAGE();
END CATCH;

ROLLBACK;
