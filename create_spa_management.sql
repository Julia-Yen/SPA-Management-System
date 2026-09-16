
-- Force disconnect all users, including your session
USE master;
GO
ALTER DATABASE spa_management 
SET SINGLE_USER 
WITH ROLLBACK IMMEDIATE;
GO

DROP DATABASE spa_management;
GO

CREATE DATABASE spa_management;
GO

USE spa_management;

GO

-- ====================================================================
-- 1. BẢNG KHÁCH HÀNG (CUSTOMERS)
-- ====================================================================
CREATE TABLE khach_hang (
    ma_khach_hang INT IDENTITY(1,1) PRIMARY KEY,
    ho_ten NVARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(15) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    mat_khau VARBINARY(64) NOT NULL,
    ngay_sinh DATE,
    gioi_tinh NVARCHAR(10) CHECK (gioi_tinh IN(N'Nam', N'Nữ', N'Khác')),
    ngay_dang_ky DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    loai_da NVARCHAR(20) CHECK (loai_da IN (N'khô', N'dầu', N'hỗn hợp', N'nhạy cảm', N'bình thường')) DEFAULT N'bình thường',
    so_lan_huy INT DEFAULT 0,
    cap_thanh_vien NVARCHAR(20) CHECK (cap_thanh_vien IN (N'thường', N'vip', N'kim cương')) DEFAULT N'thường',
    trang_thai NVARCHAR(20) CHECK (trang_thai IN (N'hoạt động', N'tạm khóa', N'ngừng hoạt động')) DEFAULT N'hoạt động',
    lan_den_cuoi DATETIME2, 
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE()
);
GO
-- ====================================================================
-- 2. BẢNG DỊCH VỤ (SERVICES)
-- ====================================================================
CREATE TABLE dich_vu (
    ma_dich_vu INT IDENTITY(1,1) PRIMARY KEY,
    ten_dich_vu NVARCHAR(150) NOT NULL,
    mo_ta NTEXT,
    phan_loai NVARCHAR(20) CHECK (phan_loai IN (N'massage', N'chăm sóc da', N'tắm trắng', N'nail', N'tóc', N'khác')) NOT NULL,
    gia INT NOT NULL,
    thoi_gian INT NOT NULL,
    diem_tich_luy INT DEFAULT 0,
    trang_thai NVARCHAR(20) CHECK (trang_thai IN (N'hoạt động', N'ngừng phục vụ', N'bảo trì')) DEFAULT N'hoạt động',
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT chk_gia CHECK (gia > 0),
    CONSTRAINT chk_thoi_gian CHECK (thoi_gian > 0)
);
GO

-- ====================================================================
-- 3. BẢNG NHÂN VIÊN (EMPLOYEES)
-- ====================================================================
CREATE TABLE nhan_vien (
    ma_nhan_vien INT IDENTITY(1,1) PRIMARY KEY,
    ho_ten NVARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(15) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    ngay_sinh DATE,
    gioi_tinh NVARCHAR(10) CHECK (gioi_tinh IN (N'Nam', N'Nữ', N'Khác')),
    so_cccd VARCHAR(20) UNIQUE,
    dia_chi NVARCHAR(255),
    chuyen_mon NVARCHAR(255) NOT NULL,
    ngay_bat_dau_lam DATE NULL,
    mat_khau VARBINARY(255) NOT NULL,
    chuc_vu NVARCHAR(20) CHECK (chuc_vu IN (N'quản lý', N'nhân viên')) DEFAULT N'nhân viên',
    diem_danh_gia DECIMAL(3,2) DEFAULT 0.00,
    so_khach_phuc_vu INT DEFAULT 0,
    trang_thai NVARCHAR(20) CHECK (trang_thai IN (N'làm việc', N'nghỉ việc')) DEFAULT N'làm việc',
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT chk_diem_danh_gia CHECK (diem_danh_gia >= 0 AND diem_danh_gia <= 5)
);
GO

-- ====================================================================
-- 4. BẢNG PHÒNG DỊCH VỤ (SERVICE ROOMS)
-- ====================================================================
CREATE TABLE phong_dich_vu (
    ma_phong INT IDENTITY(1,1) PRIMARY KEY,
    ten_phong NVARCHAR(50) NOT NULL,
    ma_dich_vu INT, 
    loai_phong NVARCHAR(20) CHECK (loai_phong IN (N'đơn', N'đôi', N'vip')) NOT NULL,
    suc_chua INT NOT NULL CHECK (suc_chua > 0),
    trang_thai NVARCHAR(20) CHECK (trang_thai IN (N'hoạt động', N'bảo trì', N'ngừng hoạt động')) DEFAULT N'hoạt động',
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_phong_dich_vu_chuyen_dung FOREIGN KEY (ma_dich_vu) REFERENCES dich_vu(ma_dich_vu)
);
GO

-- ====================================================================
-- 5. BẢNG CHƯƠNG TRÌNH ƯU ĐÃI (PROMOTIONS)
-- ====================================================================
CREATE TABLE chuong_trinh_uu_dai (
    ma_uu_dai INT IDENTITY(1,1) PRIMARY KEY,
    ten_chuong_trinh NVARCHAR(150) NOT NULL,
    ma_khuyen_mai VARCHAR(50) UNIQUE,
    loai_giam VARCHAR(20) CHECK (loai_giam IN ('phần trăm', 'số tiền cố định')) NOT NULL,
    gia_tri_giam DECIMAL(10,2) NOT NULL,
    ngay_bat_dau DATE NOT NULL,
    ngay_ket_thuc DATE NOT NULL,
    gia_tri_toi_thieu DECIMAL(10,2) DEFAULT 0,
    gioi_han_su_dung INT DEFAULT NULL,
    so_lan_su_dung INT DEFAULT 0,
    cap_thanh_vien_yeu_cau VARCHAR(20) CHECK (cap_thanh_vien_yeu_cau IN ('thường', 'vip', 'kim cương')) DEFAULT 'thường',
    khach_hang_moi BIT DEFAULT 0,
    trang_thai VARCHAR(20) CHECK (trang_thai IN ('hiệu lực', 'hết hạn', 'ngừng áp dụng')) DEFAULT 'hiệu lực',
    mo_ta NTEXT,
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT chk_gia_tri_giam CHECK (gia_tri_giam > 0),
    CONSTRAINT chk_ngay_uu_dai CHECK (ngay_ket_thuc >= ngay_bat_dau),
    CONSTRAINT chk_gioi_han CHECK (gioi_han_su_dung IS NULL OR gioi_han_su_dung > 0)
);
GO


-- ====================================================================
-- 6. BẢNG LỊCH HẸN (APPOINTMENTS)
-- ====================================================================
CREATE TABLE lich_hen (
    ma_lich_hen INT IDENTITY(1,1) PRIMARY KEY,
    ma_khach_hang INT NOT NULL,
    ngay_dat DATETIME2 DEFAULT GETDATE(),
    ngay_hen DATE NOT NULL,
    gio_bat_dau TIME NOT NULL,
    gio_ket_thuc TIME NOT NULL,
    tong_tien DECIMAL(10,2) NOT NULL DEFAULT 0,
    trang_thai NVARCHAR(20) CHECK (trang_thai IN (N'đặt', N'xác nhận', N'đang thực hiện', N'hoàn thành', N'hủy', N'không đến')) DEFAULT N'đặt',
    nhac_nho BIT DEFAULT 0,
    ghi_chu NTEXT,
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_lich_hen_khach_hang FOREIGN KEY (ma_khach_hang) REFERENCES khach_hang(ma_khach_hang),
    CONSTRAINT chk_gio_hen CHECK (gio_ket_thuc > gio_bat_dau),
    CONSTRAINT chk_tong_tien CHECK (tong_tien >= 0)
);
GO

-- ====================================================================
-- 7. BẢNG CHI TIẾT LỊCH HẸN (APPOINTMENT DETAILS)  
-- ====================================================================
CREATE TABLE chi_tiet_lich_hen (
    ma_ctlh INT IDENTITY(1,1) PRIMARY KEY,
    ma_lich_hen INT NOT NULL, 
    ma_dich_vu INT NOT NULL,
    ma_phong INT NOT NULL,
    thoi_gian_bat_dau DATETIME2 NOT NULL,
    thoi_gian_ket_thuc DATETIME2 NOT NULL,
    CONSTRAINT fk_ctlh_lich_hen FOREIGN KEY (ma_lich_hen) REFERENCES lich_hen(ma_lich_hen),
    CONSTRAINT fk_ctlh_dich_vu FOREIGN KEY (ma_dich_vu) REFERENCES dich_vu(ma_dich_vu),
    CONSTRAINT fk_ctlh_phong FOREIGN KEY (ma_phong) REFERENCES phong_dich_vu(ma_phong),
    CONSTRAINT chk_thoi_gian_ctlh CHECK (thoi_gian_ket_thuc > thoi_gian_bat_dau)
);
GO


-- ====================================================================
-- 8. BẢNG HÓA ĐƠN (INVOICES)
-- ====================================================================
CREATE TABLE hoa_don (
    ma_hoa_don INT IDENTITY(1,1) PRIMARY KEY,
    ma_khach_hang INT NOT NULL,
    ma_nhan_vien INT NOT NULL,
    ma_uu_dai INT NULL,
    ma_lich_hen INT NULL,  
    ngay_xuat DATETIME2 DEFAULT GETDATE(),
    tong_so_dich_vu INT DEFAULT 0 CHECK (tong_so_dich_vu >= 0),
    tong_thoi_gian INT DEFAULT 0 CHECK (tong_thoi_gian >= 0),
    tong_diem_tich_luy INT DEFAULT 0 CHECK (tong_diem_tich_luy >= 0),
    tong_tien_goc INT DEFAULT 0 CHECK (tong_tien_goc >= 0),
    diem_su_dung INT DEFAULT 0 CHECK (diem_su_dung >= 0),
    ty_le_giam DECIMAL(5,2) DEFAULT 0 CHECK (ty_le_giam >= 0 AND ty_le_giam <= 100),
    tien_giam INT DEFAULT 0 CHECK (tien_giam >= 0),
    gia_tri_diem INT DEFAULT 0 CHECK (gia_tri_diem >= 0),
    tong_thanh_toan AS (
        CASE 
            WHEN tong_tien_goc - tien_giam - gia_tri_diem < 0 THEN 0 
            ELSE tong_tien_goc - tien_giam - gia_tri_diem
        END
    ) PERSISTED,
    phuong_thuc NVARCHAR(20) NOT NULL CHECK (
        phuong_thuc IN (N'tiền mặt', N'chuyển khoản', N'thẻ', N'ví điện tử', N'hỗn hợp')
    ),
    trang_thai NVARCHAR(20) DEFAULT N'chờ thanh toán' CHECK (
        trang_thai IN (N'chờ thanh toán', N'đã thanh toán', N'hủy', N'hoàn tiền')
    ),
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_hoa_don_khach_hang FOREIGN KEY (ma_khach_hang) REFERENCES khach_hang(ma_khach_hang),
    CONSTRAINT fk_hd_nhan_vien FOREIGN KEY (ma_nhan_vien) REFERENCES nhan_vien(ma_nhan_vien),
    CONSTRAINT fk_hoa_don_uu_dai FOREIGN KEY (ma_uu_dai) REFERENCES chuong_trinh_uu_dai(ma_uu_dai),
    CONSTRAINT fk_hoa_don_lich_hen FOREIGN KEY (ma_lich_hen) REFERENCES lich_hen(ma_lich_hen) 
);
GO
-- ====================================================================
-- 9. BẢNG CHI TIẾT HÓA ĐƠN (INVOICE SERVICE DETAILS)
-- ====================================================================
CREATE TABLE chi_tiet_hoa_don (
    ma_cthd INT IDENTITY(1,1) PRIMARY KEY,
    ma_hoa_don INT NOT NULL,
    ma_dich_vu INT NOT NULL,
    ma_nhan_vien INT NOT NULL,
    so_luong INT NOT NULL DEFAULT 1 CHECK (so_luong > 0),
    gia_dv INT CHECK (gia_dv >= 0),
    thoi_gian_dv INT,
    tong_thoi_gian AS (so_luong * thoi_gian_dv) PERSISTED,
    diem_tich_luy_dv INT DEFAULT 0,
    tong_diem_tich_luy AS (so_luong * diem_tich_luy_dv) PERSISTED,
    thanh_tien AS (so_luong * gia_dv) PERSISTED,
    ghi_chu NVARCHAR(300),
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_cthd_hoa_don FOREIGN KEY (ma_hoa_don) REFERENCES hoa_don(ma_hoa_don),
    CONSTRAINT fk_cthd_nhan_vien FOREIGN KEY (ma_nhan_vien) REFERENCES nhan_vien(ma_nhan_vien),
    CONSTRAINT fk_cthd_dich_vu FOREIGN KEY (ma_dich_vu) REFERENCES dich_vu(ma_dich_vu), 
    CONSTRAINT uk_chi_tiet_hoa_don UNIQUE (ma_hoa_don, ma_dich_vu, ma_nhan_vien) -- 
);
GO
-- ====================================================================
-- 10. BẢNG LỊCH SỬ SỬ DỤNG PHÒNG (ROOM USAGE HISTORY)
-- ====================================================================
CREATE TABLE lich_su_su_dung_phong (
    ma_su_dung INT IDENTITY(1,1) PRIMARY KEY,
    ma_phong INT NOT NULL,
    ma_ctlh INT NOT NULL,
    thoi_gian_bat_dau DATETIME2 NOT NULL,
    thoi_gian_ket_thuc DATETIME2 NULL,
    trang_thai NVARCHAR(20) CHECK (trang_thai IN (N'đặt lịch', N'đang sử dụng', N'trống', N'đã hoàn thành')) DEFAULT N'đặt lịch',
    ghi_chu NVARCHAR(255),
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_sdp_phong FOREIGN KEY (ma_phong) REFERENCES phong_dich_vu(ma_phong),
    CONSTRAINT fk_sdp_ctlh FOREIGN KEY (ma_ctlh) REFERENCES chi_tiet_lich_hen(ma_ctlh)
);
GO

-- ====================================================================
-- 11. BẢNG ĐIỂM TÍCH LŨY (LOYALTY POINTS)
-- ====================================================================
CREATE TABLE diem_tich_luy (
    ma_giao_dich INT IDENTITY(1,1) PRIMARY KEY,
    ma_khach_hang INT NOT NULL,
    ma_hoa_don INT NOT NULL,
    ngay_giao_dich DATETIME2 DEFAULT GETDATE(),
    so_diem INT NOT NULL,
    loai_giao_dich NVARCHAR(20) CHECK (loai_giao_dich IN (N'tích lũy', N'sử dụng', N'điều chỉnh', N'hết hạn')) NOT NULL,
    ngay_het_han DATE,
    ghi_chu NTEXT,
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_diem_khach_hang FOREIGN KEY (ma_khach_hang) REFERENCES khach_hang(ma_khach_hang),
    CONSTRAINT fk_diem_hoa_don FOREIGN KEY (ma_hoa_don) REFERENCES hoa_don(ma_hoa_don)
);
GO
-- ====================================================================
-- 12. BẢNG ĐÁNH GIÁ DỊCH VỤ (SERVICE REVIEWS)
-- ====================================================================
CREATE TABLE danh_gia_dich_vu (
    ma_danh_gia INT IDENTITY(1,1) PRIMARY KEY,
    ma_cthd INT NOT NULL,
    diem_so DECIMAL(2,1) NOT NULL,
    noi_dung NTEXT,
    ngay_danh_gia DATETIME2 DEFAULT GETDATE(),
    diem_dich_vu DECIMAL(2,1) NOT NULL,
    diem_nhan_vien DECIMAL(2,1) NOT NULL,
    phan_hoi_spa NTEXT,
    ngay_phan_hoi DATETIME2 NULL,
    trang_thai VARCHAR(20) CHECK (trang_thai IN ('hiển thị', 'ẩn', 'chờ duyệt')) DEFAULT 'hiển thị',
    ngay_tao DATETIME2 DEFAULT GETDATE(),
    ngay_cap_nhat DATETIME2 DEFAULT GETDATE(),
	CONSTRAINT fk_dg_cthd FOREIGN KEY (ma_cthd) REFERENCES chi_tiet_hoa_don(ma_cthd),
	CONSTRAINT chk_diem_so CHECK (diem_so >= 1.0 AND diem_so <= 5.0),
    CONSTRAINT chk_diem_dv CHECK (diem_dich_vu >= 1.0 AND diem_dich_vu <= 5.0),
    CONSTRAINT chk_diem_nv CHECK (diem_nhan_vien >= 1.0 AND diem_nhan_vien <= 5.0)
);
GO