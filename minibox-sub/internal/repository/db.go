package repository

import (
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func InitDB(path string) (*gorm.DB, error){
	// 使用只读模式 + 这里的 logger 设置为 Silent，防止控制台被 SQL 刷屏
	db, err := gorm.Open(sqlite.Open(path+"?mode=ro"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		return nil, err
	}
	return db, nil
}