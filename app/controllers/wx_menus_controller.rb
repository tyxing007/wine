# encoding: UTF-8
require 'json'
require 'rest_client'

class WxMenusController < ApplicationController
  authorize_resource
  respond_to :html, :json
  before_action :set_wx_menu, only: [:show, :edit, :update, :destroy]

  skip_before_filter :verify_authenticity_token, only: [:update_via_json,
                                                        :create_via_ajax,
                                                        :destroy_via_ajax,
                                                        :create_menu_name]

  def index
    @wx_menus = WxMenu.where(level: 1).last 3
  end

  def create_menu_name
    wx_menu_params = {
      name: params[:name],
      parent_id: params[:parent_id], # 第一级菜单 0
      level: params[:level] # 第一级菜单 1
    }
    @wx_menu = WxMenu.new(wx_menu_params)
    if @wx_menu.save
      render json: { status: 'success', msg: 'create menu success' }
    else
      render json: { status: 'error', msg: 'create menu failed' }
    end
  end

  def update_via_json
    mu = WxMenu.find params[:pk]
    mu.name = params[:value] if params[:name] == 'name'
    mu.url = params[:value] if params[:name] == 'url'
    if mu.save
      render json: { status: 'success', msg: 'update success' }
    else
      render json: { status: 'error', msg: 'update failed' }
    end
  end

  def create_weixin_menu
    access_token_hash = get_access_token('wxa2bbd3b7a22039df', 'client_credential', '724bbaea1bce4c09865c2c47acbf450d')

    res_hash = create_custom_menu(access_token_hash['access_token'])
    puts '-' * 20
    puts res_hash
    if res_hash['errcode'] == 0 && res_hash['errmsg'] == 'ok'
      render json: { status: 'success', msg: 'create menu success' }
    else
      render json: { status: 'error', msg: 'create menu failed' }
    end
  end

  def create_via_ajax
    wx_menu_params = {
      name: params[:name],
      msg: '',
      url: params[:url],
      msg_or_url: 1,
      button_type: 'view',
      key: '',
      parent_id: params[:parent_id],
      level: params[:level]
    }
    @wx_menu = WxMenu.new(wx_menu_params)
    if @wx_menu.save
      render json: { status: 'success', msg: 'create menu success' }
    else
      render json: { status: 'error', msg: 'create menu failed' }
    end
  end

  def destroy_via_ajax
    @wx_menu = WxMenu.find(params[:id])
    sub_menus = WxMenu.where(level:2, parent_id: @wx_menu.id)
    if @wx_menu.destroy
      unless sub_menus.blank?
        sub_menus.each do |m|
          m.destroy!
        end
      end
      render json: { status: 'success', msg: 'del menu success' }
    else
      render json: { status: 'error', msg: 'del menu failed' }
    end
  end

  def show
    respond_with(@wx_menu)
  end

  def new
    @wx_menu = WxMenu.new
    respond_with(@wx_menu)
  end

  def edit
  end

  def create
    @wx_menu = WxMenu.new(wx_menu_params)
    flash[:notice] = 'WxMenu was successfully created.' if @wx_menu.save
    respond_with(@wx_menu)
  end

  def update
    flash[:notice] = 'WxMenu was successfully updated.' if @wx_menu.update(wx_menu_params)
    respond_with(@wx_menu)
  end

  def destroy
    @wx_menu.destroy
    respond_with(@wx_menu)
  end

  private

  def set_wx_menu
    @wx_menu = WxMenu.find(params[:id])
  end

  def wx_menu_params
    params.require(:wx_menu).permit(:name, :msg, :url, :msg_or_url, :button_type, :key, :parent_id, :level)
  end

  def get_access_token(appid = 'wxa2bbd3b7a22039df', grant_type = 'client_credential', secret = '724bbaea1bce4c09865c2c47acbf450d')
    url = "https://api.weixin.qq.com/cgi-bin/token?grant_type=#{grant_type}&appid=#{appid}&secret=#{secret}"
    res = RestClient.get url
    JSON.parse res
  end

  def get_custom_menu(access_token)
    url = "https://api.weixin.qq.com/cgi-bin/menu/get?access_token=#{access_token}"
    res = RestClient.get url
    JSON.parse res
  end

  def create_custom_menu(access_token)
    menus = { button: [] }
    top_mus = WxMenu.where(level: 1).last 3
    top_mus.each do |tm|
      tmp_hash = {
        name: tm.name,
        sub_button: []
      }
      WxMenu.where(level: 2, parent_id: tm.id).last(5).each do |sm|
        tmp_hash[:sub_button].push(
          type: 'view',
          name: sm.name,
          url: sm.url
        )
      end
      menus[:button].push tmp_hash
    end

    json = menus.to_json.gsub!(/\\u([0-9a-z]{4})/) { |s| [$1.to_i(16)].pack('U') }

    json = menus.to_json if json.blank?

    url = "https://api.weixin.qq.com/cgi-bin/menu/create?access_token=#{access_token}"
    res = RestClient.post url, json
    JSON.parse res
  end
end
