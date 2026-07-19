begin;

insert into public.legal_documents
  (document_type, version, locale, title, content_hash, required, active)
values
  ('terms','1.0.0-draft','tr-TR','Kullanım Koşulları','ac3f18aa03b4e453bce2a49ad4ec5b5b20c88d4ceb626db7028539ca87518c40',true,true),
  ('community_rules','1.0.0-draft','tr-TR','Topluluk Kuralları','421d32c016063642fd33316713a34d1d62b9b1f297366821c1793de770fb284d',true,true),
  ('privacy_notice','1.0.0-draft','tr-TR','Gizlilik ve KVKK Aydınlatma Metni','16a8aa457017f4b4d087e412d08ec15252ed16111ca2f3fd7094956ffabfd0a8',true,true),
  ('analytics_consent','1.0.0-draft','tr-TR','İsteğe Bağlı Analitik Açık Rızası','5c6c09963a7c1b0dbfc8271d7904bc83a35cfa2fee4e7fbf379d208acd8c6330',false,true)
on conflict (document_type, version, locale) do update set
  title = excluded.title,
  content_hash = excluded.content_hash,
  required = excluded.required,
  active = excluded.active;

commit;
