-- Revision 3 (Oct 2026): PDRRMO <-> MDRRMO/CDRRMO coordination channel.
-- The API creates these tables by itself (App\Models\CoordinationMessage); import manually only if the DB user lacks CREATE.

DROP TABLE IF EXISTS `lgu_messages`;
CREATE TABLE IF NOT EXISTS `lgu_messages` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `municipality_id` bigint(20) unsigned DEFAULT NULL,
  `sender_id` bigint(20) unsigned NOT NULL,
  `direction` enum('to_lgu','to_province') NOT NULL,
  `category` enum('advisory','directive','situation_report','request','response','general') NOT NULL DEFAULT 'general',
  `priority` enum('normal','urgent','critical') NOT NULL DEFAULT 'normal',
  `subject` varchar(180) NOT NULL,
  `body` text NOT NULL,
  `requires_ack` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_lgu_messages_channel` (`municipality_id`,`created_at`),
  KEY `fk_lgu_message_sender` (`sender_id`),
  CONSTRAINT `fk_lgu_message_municipality` FOREIGN KEY (`municipality_id`) REFERENCES `municipalities` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_lgu_message_sender` FOREIGN KEY (`sender_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `lgu_message_acks`;
CREATE TABLE IF NOT EXISTS `lgu_message_acks` (
  `message_id` bigint(20) unsigned NOT NULL,
  `municipality_id` bigint(20) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `acknowledged_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`message_id`,`municipality_id`),
  KEY `fk_lgu_ack_municipality` (`municipality_id`),
  KEY `fk_lgu_ack_user` (`user_id`),
  CONSTRAINT `fk_lgu_ack_message` FOREIGN KEY (`message_id`) REFERENCES `lgu_messages` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_lgu_ack_municipality` FOREIGN KEY (`municipality_id`) REFERENCES `municipalities` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_lgu_ack_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
DROP TABLE IF EXISTS `lgu_channel_reads`;
CREATE TABLE IF NOT EXISTS `lgu_channel_reads` (
  `user_id` bigint(20) unsigned NOT NULL,
  `municipality_id` bigint(20) unsigned NOT NULL,
  `last_read_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`user_id`,`municipality_id`),
  KEY `fk_lgu_read_municipality` (`municipality_id`),
  CONSTRAINT `fk_lgu_read_municipality` FOREIGN KEY (`municipality_id`) REFERENCES `municipalities` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_lgu_read_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


