package repository

import (
	"minibox-sub/internal/model"

	"gorm.io/gorm"
)

type InboundRepository struct {
	db *gorm.DB
}

func NewInboundRepository(db *gorm.DB) *InboundRepository {
	return &InboundRepository{db: db}
}

// FindAll 获取所有节点
func (r *InboundRepository) FindAll() ([]model.Inbound, error) {
	var inbounds []model.Inbound
	result := r.db.Find(&inbounds)
	return inbounds, result.Error
}

// FindByID 根据 ID 获取单个节点
func (r *InboundRepository) FindByID(id int) (*model.Inbound, error) {
	var inbound model.Inbound
	result := r.db.First(&inbound, id)
	if result.Error != nil {
		return nil, result.Error
	}
	return &inbound, nil
}

// FindByIDs 根据 ID 列表批量获取节点
func (r *InboundRepository) FindByIDs(ids []int) ([]model.Inbound, error) {
	var inbounds []model.Inbound
	if len(ids) == 0 {
		return inbounds, nil
	}
	result := r.db.Where("id IN ?", ids).Find(&inbounds)
	return inbounds, result.Error
}
