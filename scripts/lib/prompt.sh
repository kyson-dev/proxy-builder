#!/bin/bash
# ==============================================================================
# 交互式提示库
# 依赖: common.sh (由主脚本预先加载)
# ==============================================================================

# 防止重复加载
[[ -n "${_LIB_PROMPT_LOADED:-}" ]] && return 0
_LIB_PROMPT_LOADED=1


# ------------------------------------------------------------------------------
# 选择函数
# ------------------------------------------------------------------------------

# 从列表中选择
# 用法: select_from_list "提示信息" "选项1" "选项2" ...
# 返回: 选中的索引 (0-based) 通过 $SELECTED_INDEX
#       选中的值通过 $SELECTED_VALUE
select_from_list() {
    local prompt="$1"
    shift
    local options=("$@")
    
    echo ""
    local i=1
    for opt in "${options[@]}"; do
        echo "  $i. $opt"
        ((i++))
    done
    echo "  0. 手动输入"
    echo ""
    
    while true; do
        read -p "$prompt (0-${#options[@]}): " selection
        
        if [[ "$selection" == "0" ]]; then
            read -p "请输入: " SELECTED_VALUE
            SELECTED_INDEX=-1
            return 0
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "${#options[@]}" ]]; then
            SELECTED_INDEX=$((selection - 1))
            SELECTED_VALUE="${options[$SELECTED_INDEX]}"
            return 0
        fi
        
        echo "无效选择，请重试。"
    done
}

# 带默认值的选择
# 用法: select_with_default "提示信息" "默认值" "选项1" "选项2" ...
select_with_default() {
    local prompt="$1"
    local default="$2"
    shift 2
    local options=("$@")
    
    echo ""
    local i=1
    local default_index=-1
    for opt in "${options[@]}"; do
        if [[ "$opt" == "$default" ]]; then
            echo "  $i. $opt (当前)"
            default_index=$((i - 1))
        else
            echo "  $i. $opt"
        fi
        ((i++))
    done
    echo "  0. 手动输入"
    echo ""
    
    while true; do
        read -p "$prompt [默认: $default]: " selection
        
        # 空输入使用默认值
        if [[ -z "$selection" ]] && [[ -n "$default" ]]; then
            SELECTED_VALUE="$default"
            SELECTED_INDEX=$default_index
            return 0
        fi
        
        if [[ "$selection" == "0" ]]; then
            read -p "请输入: " SELECTED_VALUE
            SELECTED_INDEX=-1
            return 0
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le "${#options[@]}" ]]; then
            SELECTED_INDEX=$((selection - 1))
            SELECTED_VALUE="${options[$SELECTED_INDEX]}"
            return 0
        fi
        
        echo "无效选择，请重试。"
    done
}

# ------------------------------------------------------------------------------
# 确认函数
# ------------------------------------------------------------------------------

# 确认是/否
# 用法: confirm "提示信息" [默认值 y/n]
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    local yn_hint
    if [[ "$default" == "y" ]]; then
        yn_hint="[Y/n]"
    else
        yn_hint="[y/N]"
    fi
    
    while true; do
        read -p "$prompt $yn_hint: " -n 1 -r response
        echo
        
        # 空输入使用默认值
        if [[ -z "$response" ]]; then
            [[ "$default" == "y" ]] && return 0 || return 1
        fi
        
        case "$response" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 输入函数
# ------------------------------------------------------------------------------

# 带默认值的输入
# 用法: prompt_with_default "提示信息" "默认值"
# 返回: 输入值通过 $INPUT_VALUE
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    
    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " INPUT_VALUE
        INPUT_VALUE="${INPUT_VALUE:-$default}"
    else
        read -p "$prompt: " INPUT_VALUE
    fi
}

# 必填输入
# 用法: prompt_required "提示信息" "错误信息"
# 返回: 输入值通过 $INPUT_VALUE
prompt_required() {
    local prompt="$1"
    local error_msg="${2:-此字段为必填项}"
    
    while true; do
        read -p "$prompt: " INPUT_VALUE
        if [[ -n "$INPUT_VALUE" ]]; then
            return 0
        fi
        log_warn "$error_msg"
    done
}

# 密码输入 (隐藏输入)
# 用法: prompt_password "提示信息"
# 返回: 密码通过 $INPUT_VALUE
prompt_password() {
    local prompt="$1"
    read -sp "$prompt: " INPUT_VALUE
    echo
}

# ------------------------------------------------------------------------------
# 菜单函数
# ------------------------------------------------------------------------------

# 显示菜单并获取选择
# 用法: show_menu "标题" "选项1|描述1" "选项2|描述2" ...
# 返回: 选中的索引通过 $MENU_SELECTION
show_menu() {
    local title="$1"
    shift
    local options=("$@")
    
    echo ""
    echo -e "${BOLD}$title${NC}"
    echo ""
    
    local i=1
    for opt in "${options[@]}"; do
        local label="${opt%%|*}"
        local desc="${opt#*|}"
        if [[ "$label" == "$desc" ]]; then
            echo "  $i. $label"
        else
            echo "  $i. $label"
            echo "     $desc"
        fi
        ((i++))
    done
    echo "  0. 退出"
    echo ""
    
    while true; do
        read -p "选择 (0-${#options[@]}): " MENU_SELECTION
        
        if [[ "$MENU_SELECTION" == "0" ]]; then
            return 1
        fi
        
        if [[ "$MENU_SELECTION" =~ ^[0-9]+$ ]] && \
           [[ "$MENU_SELECTION" -ge 1 ]] && \
           [[ "$MENU_SELECTION" -le "${#options[@]}" ]]; then
            return 0
        fi
        
        echo "无效选择，请重试。"
    done
}
