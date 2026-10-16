-- =====================================================================
-- 049: Danh mục hãng xe / dòng xe đầy đủ (xe con, bán tải, xe khách nhỏ, tải nhẹ thường gặp ở Việt Nam)
--  - Gồm xe đang bán chính hãng (bảng giá tháng 9–10/2026) + đời cũ còn chạy nhiều ngoài đường.
--  - Tên dòng xe chỉ là "dòng" (Vios, CR-V, VF8…), không ghi phiên bản; phiên bản ghi ở ghi chú hồ sơ.
--  - CHỈ THÊM: hãng / dòng đã có giữ nguyên id (hồ sơ, xe cũ không bị ảnh hưởng). Chạy lại nhiều lần không sao.
--  - Hãng "Mercedes", "Khác", "MPV 7" (VinFast VF MPV 7) giữ tên đang dùng. Trùng cách viết (CX5 / CX-5, hoa / thường) thì bỏ qua.
--  - Mỗi hãng có thêm dòng "Khác" (xe hiếm chưa có trong danh sách). Dòng nào chưa có thì vào Danh mục > Dòng xe thêm.
-- =====================================================================

with ds(hang, dong) as (values
  ('VinFast',    array['VF2','VF3','VF5','VF5 Plus','VF6','VF6 Plus','VF7','VF8','VF8 All New','VF9','VF e34','MPV 7',
                       'Limo Green','Minio Green','Nerio Green','Herio','EC Van',
                       'Fadil','Lux A2.0','Lux SA2.0','President']),
  ('Toyota',     array['Wigo','Vios','Yaris','Yaris Cross','Corolla','Corolla Altis','Corolla Cross','Camry','Crown','Avalon',
                       'Raize','Rush','Avanza','Avanza Premio','Veloz','Innova','Innova Cross','Zace','Wish','Previa','Sienna',
                       'Alphard','Fortuner','Hilux','Land Cruiser','Land Cruiser Prado','4Runner','Highlander','RAV4','Venza',
                       'Prius','FJ Cruiser','86','Hiace']),
  ('Hyundai',    array['Grand i10','i10','i20','i30','Getz','Click','Accent','Verna','Avante','Elantra','Sonata','Genesis',
                       'Venue','Kona','Creta','Stargazer','Tucson','Santa Fe','Palisade','Veracruz','Custin','Ioniq 5',
                       'Veloster','Starex','Grand Starex','Staria','Solati','County','Porter','Mighty','H100']),
  ('Kia',        array['Morning','Picanto','Soluto','Pride','Rio','K3','Cerato','Forte','Spectra','K5','Optima','Quoris',
                       'Stinger','Sonet','Seltos','Carens','Rondo','Soul','Sportage','Sorento','Carnival','Sedona',
                       'EV5','EV6','EV9','Frontier K200','K250','K2700','Bongo']),
  ('Mazda',      array['Mazda 2','Mazda 3','Mazda 6','323','626','Premacy','MX-5','CX-3','CX-30','CX-5','CX-8','CX-9','BT-50']),
  ('Mitsubishi', array['Attrage','Mirage','Lancer','Xpander','Xpander Cross','Xforce','Destinator','Outlander','Outlander Sport',
                       'Pajero','Pajero Sport','Grandis','Zinger','Jolie','Triton']),
  ('Honda',      array['Brio','City','Civic','Civic Type R','Accord','Jazz','Fit','BR-V','HR-V','WR-V','CR-V','Odyssey','Pilot']),
  ('Ford',       array['Fiesta','Focus','Laser','Mondeo','EcoSport','Escape','Territory','Everest','Explorer','Ranger',
                       'Ranger Raptor','F-150','Mustang','Mustang Mach-E','Transit','Tourneo']),
  ('Nissan',     array['Sunny','Almera','Tiida','Teana','Livina','Grand Livina','Juke','Kicks','Qashqai','X-Trail','Murano',
                       'Terra','Navara','Patrol','Serena','Urvan','Leaf']),
  ('Suzuki',     array['Alto','Celerio','Wagon R','Swift','Ciaz','Ertiga','XL7','Fronx','Vitara','Grand Vitara','Jimny','APV',
                       'Carry','Super Carry Pro','Super Carry Truck','Blind Van']),
  ('Isuzu',      array['D-Max','mu-X','Hi Lander','Trooper','QKR','NMR','NPR','NQR','FRR']),
  ('Mercedes',   array['A-Class','B-Class','C-Class','E-Class','S-Class','CLA','CLS','CLK','GLA','GLB','GLC','GLC Coupe','GLK',
                       'GLE','GLE Coupe','ML','GL','GLS','G-Class','SL','AMG GT','EQB','EQE','EQS','Maybach S-Class',
                       'Maybach GLS','V-Class','Vito','Sprinter']),
  ('BMW',        array['1 Series','2 Series','3 Series','4 Series','5 Series','6 Series','7 Series','8 Series','X1','X2','X3',
                       'X4','X5','X6','X7','XM','Z4','i3','i4','i7','iX','iX3','M3','M4','M5']),
  ('Lexus',      array['ES','IS','GS','LS','LC','RC','UX','NX','RX','GX','LX','LM']),
  ('Audi',       array['A1','A3','A4','A5','A6','A7','A8','Q2','Q3','Q5','Q7','Q8','TT','R8','e-tron','e-tron GT']),
  ('Volkswagen', array['Polo','Virtus','Jetta','Passat','Golf','Scirocco','Beetle','T-Cross','Tiguan','Teramont','Teramont X',
                       'Touareg','Viloran','Sharan','Multivan','Transporter']),
  ('Peugeot',    array['208','2008','308','3008','408','5008','508','Traveller','Partner']),
  ('Chevrolet',  array['Spark','Aveo','Cruze','Lacetti','Vivant','Orlando','Captiva','Trax','Trailblazer','Colorado']),
  ('Daewoo',     array['Matiz','Lanos','Cielo','Nubira','Gentra','Lacetti','Magnus','Leganza']),
  ('Subaru',     array['Impreza','XV','Crosstrek','Forester','Outback','Legacy','Evoltis','BRZ','WRX']),
  ('MG',         array['MG3','MG4 EV','MG5','MG7','ZS','HS','RX5','VS HEV','G50']),
  ('BYD',        array['Dolphin','Atto 2','Atto 3','Seal','Seal 5','Sealion 6','Sealion 7','Sealion 8','M6','M9','Han']),
  ('Geely',      array['Coolray','Emgrand','Monjaro','EX5']),
  ('Lynk & Co',  array['01','03','05','06','08','09']),
  ('Omoda',      array['C5','E5']),
  ('Jaecoo',     array['J5','J7','J8']),
  ('Haval',      array['Jolion','H6']),
  ('Tank',       array['300','500']),
  ('Wuling',     array['Hongguang Mini EV','Bingo']),
  ('GAC',        array['Emzoom','Emkoo','GS8','M6 Pro','M8']),
  ('Aion',       array['Y Plus','V','ES','Hyptec HT']),
  ('Zeekr',      array['X','001','7X','009']),
  ('Skoda',      array['Kushaq','Slavia','Karoq','Kodiaq']),
  ('Volvo',      array['S60','S90','V60','V90','XC40','XC60','XC90','EX30']),
  ('Porsche',    array['911','718 Boxster','718 Cayman','Macan','Cayenne','Panamera','Taycan']),
  ('Land Rover', array['Defender','Discovery','Discovery Sport','Freelander','Range Rover','Range Rover Sport',
                       'Range Rover Velar','Range Rover Evoque']),
  ('Mini',       array['Cooper','Cooper Convertible','Clubman','Countryman','Aceman']),
  ('Jeep',       array['Wrangler','Gladiator','Grand Cherokee','Cherokee','Compass']),
  ('Ssangyong',  array['Musso','Korando','Rexton','Tivoli']),
  ('Renault',    array['Koleos','Duster','Megane']),
  ('Fiat',       array['Albea','Siena','Doblo','500']),
  ('Jaguar',     array['XE','XF','XJ','E-Pace','F-Pace','F-Type']),
  ('Maserati',   array['Ghibli','Quattroporte','Levante','Grecale']),
  ('Infiniti',   array['QX50','QX60','QX70','QX80']),
  ('Cadillac',   array['Escalade']),
  ('Tesla',      array['Model 3','Model Y','Model S','Model X']),
  ('Bentley',    array['Bentayga','Continental GT','Flying Spur']),
  ('Rolls-Royce',array['Ghost','Phantom','Cullinan','Wraith']),
  ('Thaco',      array['Tải Van','Towner','Towner Van','Frontier','Ollin','Foton','Auman'])
),
them_hang as (
  insert into public.hang_xe (ten) select hang from ds on conflict (ten) do nothing returning id, ten
),
hang as (select id, ten from them_hang union select id, ten from public.hang_xe)
insert into public.dong_xe (hang_xe_id, ten)
select h.id, d.ten
from ds cross join lateral unnest(ds.dong) as d(ten)
join hang h on h.ten = ds.hang
where not exists (select 1 from public.dong_xe c where c.hang_xe_id = h.id
                  and regexp_replace(lower(c.ten), '[^a-z0-9à-ỹđ]', '', 'g') = regexp_replace(lower(d.ten), '[^a-z0-9à-ỹđ]', '', 'g'))
on conflict (hang_xe_id, ten) do nothing;

-- Dòng "Khác" cho mọi hãng (trừ hãng "Khác" đã có sẵn dòng "Khác")
insert into public.dong_xe (hang_xe_id, ten)
select h.id, 'Khác' from public.hang_xe h
where h.ten <> 'Khác' and not exists (select 1 from public.dong_xe c where c.hang_xe_id = h.id and lower(c.ten) = 'khác')
on conflict (hang_xe_id, ten) do nothing;

notify pgrst, 'reload schema';
