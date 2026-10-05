INSERT INTO users (discord_id, username, avatar, inserted_at, updated_at)
  VALUES ('888888888888888801', 'rehearsal-user', NULL, '2026-01-01 00:00:00', '2026-01-01 00:00:00');

INSERT INTO api_tokens (user_id, token_hash, label, revoked_at, last_used_at, inserted_at, updated_at)
  VALUES ((SELECT id FROM users WHERE discord_id = '888888888888888801'), 'e5c690498e117f9e26262bb70bf76ff1330d73c1650e8685a087420a1b4919a0', 'rehearsal',
          NULL, NULL, '2026-01-01 00:00:00', '2026-01-01 00:00:00');

INSERT INTO sounds (filename, storage_key, source_type, volume, user_id, inserted_at, updated_at)
  VALUES
    ('rehearsal-one.mp3', 'f946a942-7773-48d4-840f-3a249c48bc82.mp3', 'local', 1.0, (SELECT id FROM users WHERE discord_id = '888888888888888801'), '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
    ('rehearsal-two.mp3', '2d339be2-b64e-42a7-be71-5b69042a80e8.mp3', 'local', 1.0, (SELECT id FROM users WHERE discord_id = '888888888888888801'), '2026-01-01 00:00:00', '2026-01-01 00:00:00');

INSERT INTO user_sound_settings (user_id, sound_id, is_join_sound, is_leave_sound, inserted_at, updated_at)
  SELECT user_id, id, 1, 0, '2026-01-01 00:00:00', '2026-01-01 00:00:00' FROM sounds WHERE filename = 'rehearsal-one.mp3';
