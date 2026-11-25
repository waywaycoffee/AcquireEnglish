-- 【schema.sql】
CREATE TABLE ik_reading_article (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '主键ID',
  level ENUM('初中（中考）','高中（高考）') NOT NULL COMMENT '学段',
  topic_name VARCHAR(255) NOT NULL COMMENT '主题名称',
  passage TEXT NOT NULL COMMENT '英文原文',
  word_count INT NOT NULL COMMENT '词数',
  digital_human_questions JSON NOT NULL COMMENT '数字人3条口语提问数组',
  source_type ENUM('ai_original','authorized','adapted') NOT NULL DEFAULT 'ai_original' COMMENT '来源',
  review_status ENUM('pending','passed','rejected') NOT NULL DEFAULT 'pending' COMMENT '审校状态',
  reviewer VARCHAR(64) DEFAULT NULL COMMENT '审核人',
  review_note TEXT COMMENT '审核备注',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_level (level),
  INDEX idx_review (review_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='时文阅读主文章';

CREATE TABLE ik_reading_question (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  article_id BIGINT UNSIGNED NOT NULL COMMENT '关联文章id',
  q_no TINYINT NOT NULL COMMENT '题号1-4',
  question TEXT NOT NULL COMMENT '题干英文',
  opt_a VARCHAR(512) NOT NULL,
  opt_b VARCHAR(512) NOT NULL,
  opt_c VARCHAR(512) NOT NULL,
  opt_d VARCHAR(512) NOT NULL,
  answer CHAR(1) NOT NULL COMMENT 'A/B/C/D',
  analysis TEXT NOT NULL COMMENT '解析，含原文定位',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_article (article_id),
  FOREIGN KEY (article_id) REFERENCES ik_reading_article(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='阅读题目';

CREATE TABLE ik_reading_word (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  article_id BIGINT UNSIGNED NOT NULL,
  word VARCHAR(128) NOT NULL COMMENT '单词',
  phonetic VARCHAR(128) NOT NULL COMMENT '音标',
  chinese VARCHAR(255) NOT NULL COMMENT '释义',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_article (article_id),
  INDEX idx_word (word),
  FOREIGN KEY (article_id) REFERENCES ik_reading_article(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='文章重点生词';

CREATE TABLE ik_reading_long_sentence (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  article_id BIGINT UNSIGNED NOT NULL,
  sentence TEXT NOT NULL COMMENT '原句',
  translation TEXT NOT NULL COMMENT '中文翻译',
  grammar_analysis TEXT NOT NULL COMMENT '语法拆解',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_article (article_id),
  FOREIGN KEY (article_id) REFERENCES ik_reading_article(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='长难句解析';
