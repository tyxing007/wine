class OrdersController < ApplicationController
  authorize_resource
  respond_to :html, :json
  before_action :set_order, only: [:show, :edit, :update, :destroy, :sure_order, :ship_order, :receive_order, :ok_order, :add_order_express]
  skip_before_filter :verify_authenticity_token, only: [:add_order_express]

  def index
    @orders = Order.all.paginate(page: params[:page], per_page: 10).order('id DESC')
    respond_with(@orders)
  end

  def show
    respond_with(@order)
  end

  def new
    @order = Order.new
    respond_with(@order)
  end

  def edit
  end

  def create
    @order = Order.new(order_params)
    flash[:notice] = '订单创建成功.' if @order.save
    respond_with(@order)
  end

  def update
    flash[:notice] = '订单更新成功.' if @order.update(order_params)
    respond_with(@order)
  end

  def destroy
    @order.destroy
    respond_with(@order)
  end

  # order_status: {1: 未处理, 2: 已确定, 3: 已完成, 4: 已取消}
  # pay_status: {1: 未付款, 2: 已付款}
  # logistics_status: {0: 订单还未处理, 1: 备货中, 2: 已发货, 3: 已收货, 4: 已退货}
  def index_orders_unsure
    @orders = Order.where(order_status: 1, pay_status: 2, logistics_status: 0, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  # 确定订单
  def sure_order
    @order.order_status = 2
    @order.logistics_status = 1
    @order.save
    flash[:notice] = '确定成功, 该订单已进入备货阶段'
    redirect_to action: :index_orders_unsure
  end

  # 添加快递号
  def add_order_express
    @order.express_number = params[:express_number]
    @order.express_company = params[:express_company]
    @order.express_company_number = params[:express_company_number]
    if @order.save
      render json: { status: 'success', msg: 'add order express_number success' }
    else
      render json: { status: 'failed', msg: 'add order express_number failed' }
    end
  end

  def index_orders_wait_ship
    @orders = Order.where(order_status: 2, pay_status: 2, logistics_status: 1, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  def ship_order
    @order.logistics_status = 2
    @order.save
    flash[:notice] = '发货标记成功, 该订单已进入待收货阶段'
    redirect_to action: :index_orders_wait_ship
  end

  def index_orders_already_ship
    @orders = Order.where(order_status: 2, pay_status: 2, logistics_status: 2, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  def receive_order
    @order.logistics_status = 3
    @order.save
    flash[:notice] = '收货标记成功, 该订单已进入待完成阶段'
    redirect_to action: :index_orders_already_ship
  end

  def index_orders_already_receive
    @orders = Order.where(order_status: 2, pay_status: 2, logistics_status: 3, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  def ok_order
    @order.order_status = 3
    Commission.transaction do
      Order.transaction do
        @order.save!
        buyer = @order.user
        commissioner = nil  # 第一级提成者
        total_price = @order.total_price
        commission_price = total_price.to_f  # 提成金额
        if @order.order_type == '普通订单'
          @order.products.each do |p|
            commission_price -= p.price if p.is_commission == 0
          end
        elsif @order.order_type == '团购订单'
          @order.groups.each do |g|
            commission_price -= g.price if g.is_commission == 0
          end
        elsif @order.order_type == '秒杀订单'
          @order.seckills.each do |s|
            commission_price -= s.price if s.is_commission == 0
          end
        end
        if !@order.invite_code.blank?
          commissioner_profile = Profile.where(invite_code: @order.invite_code).first
          commissioner = commissioner_profile.user
        elsif !@order.share_link_code.blank?
          commissioner_profile = Profile.where(share_link_code: @order.share_link_code).first
          commissioner = commissioner_profile.user unless commissioner_profile.blank?
        elsif !buyer.profile.parent.blank?
          commissioner_profile = buyer.profile.parent
          commissioner = commissioner_profile.user
        end
        unless commissioner.blank?
          Rails.logger.info "commissioner is #{commissioner.username}"
          vritualcard = commissioner.vritualcard
          commissioner_money = vritualcard.money.to_f
          commission_money = commission_price * 0.1
          commissioner_money += commission_money
          vritualcard.money = commissioner_money.round(2)
          vritualcard.save!

          Commission.create!(
            from_user_id: buyer.id,
            user_id: commissioner.id,
            order_id: @order.id,
            commission_money: commission_money.to_s,
            percent: '0.1'
          )

          commissioner_parent_profile = commissioner.profile.parent
          unless commissioner_parent_profile.blank?
            commissioner_parent = commissioner_parent_profile.user
            Rails.logger.info "commissioner_parent is #{commissioner_parent.username}"
            vritualcard_parent = commissioner_parent.vritualcard
            commissioner_money_parent = vritualcard_parent.money.to_f
            commission_money_parent = commission_price * 0.05
            commissioner_money_parent += commission_money_parent
            vritualcard_parent.money = commissioner_money_parent.round(2)
            vritualcard_parent.save!
            Commission.create!(
              from_user_id: buyer.id,
              user_id: commissioner_parent.id,
              order_id: @order.id,
              commission_money: commission_money_parent.to_s,
              percent: '0.05'
            )


            commissioner_parent_parent_profile = commissioner_parent.profile.parent
            unless commissioner_parent_parent_profile.blank?
              commissioner_parent_parent = commissioner_parent_parent_profile.user
              Rails.logger.info "commissioner_parent_parent is #{commissioner_parent_parent.username}"
              vritualcard_parent_parent = commissioner_parent_parent.vritualcard
              commissioner_money_parent_parent = vritualcard_parent_parent.money.to_f
              commission_money_parent_parent = commission_price * 0.01
              commissioner_money_parent_parent += commission_money_parent_parent
              vritualcard_parent_parent.money = commissioner_money_parent_parent.round(2)
              vritualcard_parent_parent.save!
              Commission.create!(
                from_user_id: buyer.id,
                user_id: commissioner_parent_parent.id,
                order_id: @order.id,
                commission_money: commission_money_parent_parent.to_s,
                percent: '0.01'
              )
            end
          end
        end
      end
    end

    flash[:notice] = '该订单已经完成'
    redirect_to action: :index_orders_already_ok
  end

  def index_orders_already_ok
    @orders = Order.where(order_status: 3, pay_status: 2, logistics_status: 3, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  def index_orders_back
    @orders = Order.where(order_status: 2, pay_status: 2, logistics_status: 4, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  def index_orders_canceled
    @orders = Order.where(order_status: 4, pay_status: 2, user_id: user_id_of_current_provider).paginate(
      page: params[:page],
      per_page: 10
    ).order('id DESC')
  end

  private

  def user_id_of_current_provider
    user_ids = []
    Profile.where(supplier_id: current_user.id).each do |p|
      user_ids.push p.user.id
    end
    user_ids
  end

  def set_order
    @order = Order.find(params[:id])
  end

  def order_params
    params.require(:order).permit(:invoice_id, :user_id, :order_number, :ship_address, :ship_method, :payment_method, :freight, :package_charge, :total_price, :buy_date, :order_status, :pay_status, :logistics_status, :operator, :cancel_reason, :weixin_open_id, :receive_name, :mobile, :tel, :supplier_id, :order_type)
  end
end
