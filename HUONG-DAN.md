# Phần mềm quản lý Gara Hoàng Sơn – Hướng dẫn cài đặt (đợt 1, chi nhánh Tô Ký)

Đợt 1 gồm: đăng nhập và phân quyền, danh mục, hồ sơ xe 10 bước, dịch vụ nhanh, thu chi, đề nghị chi, doanh thu tháng, cảnh báo việc tồn đọng.
Đợt 2 (sau): kho và mua hàng, chốt tháng và báo cáo lãi lỗ, trang cổ đông.

Toàn bộ chạy trên 3 dịch vụ miễn phí ở mức dùng của một chi nhánh:

| Dịch vụ | Dùng để | Ghi chú |
|---|---|---|
| **Supabase** | Cơ sở dữ liệu, đăng nhập, lưu ảnh | Gói Free đủ cho thử nghiệm. Khi chạy thật nên lên gói Pro (25 USD/tháng) để có sao lưu hằng ngày. |
| **GitHub** | Lưu mã nguồn | Kho riêng (private). |
| **Vercel** | Đưa trang web lên mạng | Tự cập nhật mỗi khi đẩy mã mới lên GitHub. |

---

## Cấu trúc thư mục

```
phan-mem-gara/
├── supabase/migrations/      5 tệp SQL, chạy theo thứ tự 001 → 005
│   ├── 001_bang_du_lieu.sql      các bảng
│   ├── 002_ham_nghiep_vu.sql     toàn bộ quy tắc nghiệp vụ (mọi thao tác ghi đi qua đây)
│   ├── 003_phan_quyen.sql        ai được xem gì (Row Level Security) + kho ảnh
│   ├── 004_bang_xem.sql          các bảng xem: hồ sơ, sổ quỹ, doanh thu, cảnh báo
│   └── 005_danh_muc_ban_dau.sql  danh mục ban đầu của Tô Ký
├── web/                      trang web (không cần cài đặt, không cần build)
│   ├── index.html
│   ├── css/app.css           màu sắc, bố cục (đổi màu chỉ cần sửa các biến ở đầu tệp)
│   ├── fonts/                phông Be Vietnam Pro + Barlow Condensed (giấy phép OFL, dùng tự do)
│   └── js/
│       ├── cau-hinh.js           ← ĐIỀN ĐỊA CHỈ SUPABASE VÀO ĐÂY
│       ├── app.js, api.js, ui.js
│       └── trang/                mỗi màn hình một tệp
└── test/                     bộ kiểm thử (chỉ dùng khi sửa phần mềm, không cần đưa lên mạng)
```

---

## Bước 1. Tạo dự án Supabase

1. Vào https://supabase.com, đăng nhập bằng GitHub.
2. **New project**:
   - Name: `gara-hoang-son`
   - Database password: đặt mật khẩu mạnh và **cất kỹ** (dùng khi cần sao lưu/khôi phục).
   - Region: **Southeast Asia (Singapore)** – gần Việt Nam nhất.
3. Chờ khoảng 2 phút cho dự án khởi tạo xong.

## Bước 2. Chạy 5 tệp SQL

1. Trong Supabase, mở **SQL Editor** → **New query**.
2. Mở tệp `supabase/migrations/001_bang_du_lieu.sql` bằng Notepad, chép **toàn bộ** nội dung, dán vào ô SQL, bấm **Run**.
   Phải thấy dòng `Success. No rows returned`.
3. Làm lần lượt với 002, 003, 004, 005. **Đúng thứ tự**, mỗi tệp chạy một lần.

Nếu một tệp báo lỗi: dừng lại, chụp màn hình lỗi gửi em. Đừng chạy tiếp tệp sau.

## Bước 3. Cấu hình đăng nhập

Trong Supabase → **Authentication**:

1. **Sign In / Providers** → **Email**: bật. Tắt **Allow new users to sign up** (chỉ người được mời mới vào được, người lạ không tự đăng ký được).
2. **URL Configuration** (làm sau Bước 5, khi đã có địa chỉ Vercel):
   - Site URL: `https://<tên-dự-án>.vercel.app`
   - Redirect URLs: thêm `https://<tên-dự-án>.vercel.app/**`
3. (Nên làm) **Emails → Templates**: dịch tiêu đề và nội dung 2 mẫu **Invite user** và **Reset password** sang tiếng Việt cho nhân viên dễ hiểu. Giữ nguyên `{{ .ConfirmationURL }}`.

## Bước 4. Điền địa chỉ Supabase vào trang web

1. Supabase → **Project Settings → API** (hoặc **Data API / API Keys**). Chép 2 giá trị:
   - **Project URL** (dạng `https://abcdxyz.supabase.co`)
   - Khóa **anon public** (chuỗi dài bắt đầu bằng `eyJ…`, hoặc `sb_publishable_…`)
2. Mở `web/js/cau-hinh.js`, thay 2 dòng:
   ```js
   export const SUPABASE_URL = 'https://abcdxyz.supabase.co';
   export const SUPABASE_ANON_KEY = 'eyJ...';
   ```
   Khóa anon được phép nằm công khai trong trang web: mọi quyền đã được khóa trong cơ sở dữ liệu.
   **Tuyệt đối không** dán khóa `service_role` / `secret` vào đây.

## Bước 5. Đưa lên GitHub và Vercel

1. GitHub → **New repository** → tên `phan-mem-gara`, chọn **Private** → Create.
2. Tải cả thư mục lên (kéo thả vào trang GitHub qua **uploading an existing file**, hoặc dùng GitHub Desktop).
3. Vào https://vercel.com, đăng nhập bằng GitHub → **Add New → Project** → chọn kho `phan-mem-gara`.
4. Ở màn hình cấu hình:
   - **Root Directory**: bấm Edit, chọn `web`
   - Framework Preset: **Other**
   - Build Command: để trống; Output Directory: để trống
5. **Deploy**. Xong sẽ có địa chỉ dạng `https://phan-mem-gara.vercel.app`.
6. Quay lại Bước 3.2 điền địa chỉ này vào Supabase.

Từ nay mỗi lần sửa tệp trên GitHub, Vercel tự cập nhật trang web sau khoảng 1 phút.

## Bước 6. Tạo tài khoản giám đốc (anh Thuận) – làm một lần

1. Supabase → **Authentication → Users → Add user → Send invitation**, nhập email của anh.
2. Mở email, bấm đường dẫn, đặt mật khẩu.
3. Supabase → **SQL Editor**, chạy (thay email của anh):
   ```sql
   update public.nhan_vien
   set vai_tro = '{giam_doc}', chi_nhanh_id = 'TK', ho_ten = 'Lê Ngọc Thuận'
   where email = 'email-cua-anh@gmail.com';
   ```
4. Đăng nhập trang web, sẽ thấy đủ menu.

Từ đây anh không cần SQL nữa để cấp quyền: dùng trang **Nhân viên** trong phần mềm.

## Bước 7. Mời nhân viên và cổ đông

Với từng người:
1. Supabase → Authentication → Users → **Send invitation** (email người đó).
2. Người đó mở email, bấm đường dẫn, tự đặt mật khẩu.
3. Anh vào phần mềm → **Nhân viên** → dòng của người đó → **Cấp quyền**: chọn vai trò, chi nhánh, tổ (nếu là trưởng nhóm).

| Vai trò | Ai | Thấy và làm được gì |
|---|---|---|
| Giám đốc | anh Thuận | Toàn bộ; duyệt chi trên 2 triệu; sửa cài đặt, thuế suất |
| Quản lý chung | Long | Duyệt giá, KCS, duyệt chi đến 2 triệu, duyệt giảm giá và giao xe khi khách còn nợ |
| Kế toán | Tiên | Thu chi, phân bổ tiền về hồ sơ, đề nghị chi, danh mục, doanh thu |
| Cố vấn dịch vụ | Duy | Tiếp nhận xe, báo giá, lệnh sửa chữa, giao xe, hồ sơ BH, chăm sóc |
| Kho | Duy (có thể giao người khác) | Đợt 2 |
| Trưởng nhóm | trưởng tổ ĐS / ĐMG / DT | Chỉ thấy xe của tổ mình, báo xong, báo phát sinh. Không thấy tiền, không thấy thông tin khách |
| Cổ đông | cổ đông | Chỉ xem số tổng các tháng đã chốt (trang mở ở đợt 2) |

Một người có thể giữ nhiều vai trò (ví dụ Duy: Cố vấn dịch vụ + Kho).
Nghỉ việc: bỏ chọn **Đang làm** để khóa tài khoản ngay (dữ liệu cũ giữ nguyên).

## Bước 8. Chuẩn bị số liệu trước ngày chạy thật (01/11/2026)

Làm vào ngày **31/10/2026**, sau khi đóng sổ Excel:

1. **Danh mục → Tài khoản quỹ**: với Tiền mặt, TK công ty, LP Bank nhập **Số dư đầu kỳ** = số dư cuối ngày 31/10, **Ngày đầu kỳ** = 01/11/2026 (phần mềm cộng các phiếu từ ngày này trở đi).
   Kiểm đếm tiền mặt thực tế trước khi nhập.
2. **Danh mục**: rà lại giám định viên, văn phòng bảo hiểm, nhà cung cấp, mục thu chi. Thêm cái còn thiếu.
3. **Danh mục → Cài đặt**: kiểm tra hạn mức duyệt chi (mặc định 2.000.000 đ), ngưỡng cảnh báo hoa hồng GDV (15%).
4. **Xe đang nằm xưởng và công nợ cũ** từ Excel: em sẽ làm thêm công cụ nhập từ Excel (đánh dấu "Chuyển từ Excel" để không cộng trùng doanh thu tháng 10). Anh gửi em bản Excel chốt ngày 31/10 là em chuyển.

## Thuế suất VAT

Hiện đặt 8% từ 01/01/2024. Khi giảm thuế hết hạn, anh vào **Danh mục → Thuế suất VAT**, thêm dòng: áp dụng từ `<ngày>`, tỷ lệ `0,10`.
Các hồ sơ duyệt giá trước ngày đó vẫn tính 8%, sau ngày đó tự tính 10%. Không sửa dòng cũ.

## Sao lưu

- Gói Free của Supabase **không** có sao lưu tự động. Trong thời gian thử nghiệm, mỗi tuần: Supabase → **Database → Backups**, hoặc nhờ em hướng dẫn xuất bằng `pg_dump`.
- Khi chạy thật (từ 01/11) nên lên gói **Pro** để có sao lưu tự động hằng ngày.
- Ảnh hồ sơ xe nằm trong **Storage → ho-so-xe**. Ảnh đã được nén trên điện thoại trước khi tải lên (cạnh dài tối đa 1600px) nên mỗi ảnh khoảng 200–400 KB.

## Khi cần sửa phần mềm

- Sửa giao diện: sửa tệp trong `web/`, đẩy lên GitHub, Vercel tự cập nhật.
- Sửa quy tắc nghiệp vụ hoặc thêm cột: viết tệp SQL mới `006_….sql` và chạy trong SQL Editor. **Không** chạy lại các tệp 001–005 trên dữ liệu thật (sẽ báo lỗi vì bảng đã có).
- Bộ kiểm thử (máy có PostgreSQL 16): `test/chay_kiem_thu.sh` chạy 65 bài kiểm tra nghiệp vụ. Chạy lại sau mỗi lần sửa SQL.

## Những quy tắc phần mềm tự giữ (để anh nắm khi nhân viên hỏi)

- **Không lưu báo giá khi chưa có ảnh nhận xe.** Không ký KCS đạt khi chưa có ảnh sau sửa.
- **Doanh thu ghi vào tháng duyệt giá**, số sau VAT, kèm dòng "VAT phải nộp" riêng. Hồ sơ hủy, hồ sơ bảo hành và hồ sơ chuyển từ Excel không tính doanh thu.
- **Không ai tự duyệt đề nghị chi của mình.** Trên 2 triệu chỉ giám đốc duyệt. Nhiều phiếu nhỏ cùng người, cùng mục, cùng ngày cộng lại vượt mức sẽ bị gắn cờ "Nghi tách nhỏ phiếu".
- **Kế toán chỉ chi khi đề nghị đã duyệt.** Phiếu thu của khách phải phân bổ hết vào hồ sơ/dịch vụ.
- **Giao xe khi khách còn nợ** phải có giám đốc hoặc quản lý chung duyệt.
- **Trưởng nhóm** chỉ báo xong việc của tổ mình, không xem được tiền và thông tin khách.
- Mọi thao tác trên hồ sơ đều ghi **nhật ký** (ai, lúc nào, làm gì). Hủy phiếu thu chi phải ghi lý do và vẫn giữ lại phiếu.
- Hồ sơ tự **đóng** khi đã giao xe, đã gửi hồ sơ bảo hiểm (nếu có) và đã thu đủ tiền; thu thiếu lại thì tự mở lại.
