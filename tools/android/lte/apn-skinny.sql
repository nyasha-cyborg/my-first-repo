-- Skinny NZ (MCC/MNC 530/05) per https://www.skinny.co.nz/help/device-help/devices/samsung/samsung-galaxy-s21/internet/how-to-manually-set-apn-settings
-- Apply as root: sqlite3 /data/user_de/0/com.android.providers.telephony/databases/telephony.db < apn-skinny.sql
INSERT INTO carriers (name,numeric,mcc,mnc,apn,type,protocol,roaming_protocol,carrier_enabled,user_visible,edited,current)
 VALUES ('Skinny Data','53005','530','05','wapaccess.co.nz','default,supl','IP','IP',1,1,1,1);
INSERT INTO carriers (name,numeric,mcc,mnc,apn,type,mmsc,mmsproxy,mmsport,protocol,roaming_protocol,carrier_enabled,user_visible,edited)
 VALUES ('Skinny MMS','53005','530','05','wapaccess.co.nz','mms','http://mms.mmsaccess.co.nz','210.55.11.73','80','IP','IP',1,1,1);
