package repository

import (
	"minibox-sub/internal/model"

	"gorm.io/gorm"
)

type ClientRepository struct {
	db *gorm.DB
}

func NewClientRepository(db *gorm.DB) *ClientRepository {
	return &ClientRepository{db: db}
}

// FindAllEnabled 获取所有已启用的客户端
func (r *ClientRepository) FindAllEnabled() ([]model.Client, error) {
	var clients []model.Client
	result := r.db.Where("enable = ?", 1).Find(&clients)
	return clients, result.Error
}

// FindClintByID 根据 ID 获取客户端
func (r *ClientRepository) FindByID(id int) (*model.Client, error) {
	var client model.Client
	result := r.db.First(&client, id)
	if result.Error != nil {
		return nil, result.Error
	}
	return &client, nil
}
