module Spree
  class AfterpayController < StoreController
    before_action :setup_order
    before_action :payment_method, only: [:confirm]

    def create_order
      begin
        order = current_order
        res = JSON.parse(payment_method.purchase(order))
        if order.payments.valid.present?
          redirect_to :back, notice: "seems like your payment is capture please connect to our customer service for more details before trying the payment"
        else
          redirect_to "#{payment_method.preferred_shopper_portal_url}/checkout/?token=#{res['token']}"
        end
      rescue StandardError
        redirect_to :back, notice: 'Something went wrong please try with other options'
      end
    end

    def confirm
      if params['status'] == 'SUCCESS'
        order = current_order || raise(ActiveRecord::RecordNotFound)
        payment = payment_method.capture(order, params[:orderToken], params[:PayerID])
       
        if payment == 'APPROVED'
          order.reload 
          while order.next do 
            order.next
          end
        elsif payment == 'paid'
          while order.next do 
            order.next
          end
        end
        

        if order.complete?
          flash.notice = Spree.t(:order_processed_successfully)
          flash[:order_completed] = true
          session[:order_id] = nil
          redirect_to completion_route(order)
        else
          flash[:error] = 
          if  payment != 'APPROVED'
            'Order has not completed due to payment failure'
          elsif payment == 'paid'
            "seems like your payment is capture please connect to our customer service for more details before trying the payment"
          else
            "Order has not completed due to double session , we have receiced the #{order.payments.valid.last.amount.to_s} please connect to our customer service for more details"
          end
          redirect_to checkout_state_path(order.state)
        end
      else
        flash[:error] = 'Order has not completed due to payment failure'
        redirect_to checkout_state_path(order.state)
      end
    end

    def cancel
      flash[:notice] = Spree.t('flash.cancel', scope: 'afterpay')
      order = current_order || raise(ActiveRecord::RecordNotFound)
      redirect_to checkout_state_path(order.state, afterpay_cancel_token: params[:token])
    end

    def failure
      flash[:error] = 'Order has not completed due to payment failure'
      redirect_to checkout_state_path(@order.state)
    end

    def pending
      flash[:notice] = 'Order is in process'
      redirect_to checkout_state_path(@order.state)
    end

    def error
      flash[:error] = 'Order is not completed due to payment error'
      redirect_to checkout_state_path(@order.state)
    end

    private

    def authorized?
      params[:paymentStatus] == 'AUTHORISED'
    end

    def setup_order
      @order = Spree::Order.find_by_number(params[:order_number])
    end

    # New code added from here
    def line_item(item)
      {
        Name: item.product.name,
        Number: item.variant.sku,
        Quantity: item.quantity,
        Amount: {
          currencyID: item.order.currency,
          value: item.price
        },
        ItemCategory: 'Physical'
      }
    end

    def completion_route(order)
      order_path(order)
     end

    def payment_method
      Spree::PaymentMethod.find(params[:payment_method_id])
   end
  end
end
