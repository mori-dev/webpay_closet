require 'spec_helper'
describe Customers::RegistrationsController do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:customer]
  end

  describe '#create' do
    let(:basic_params) {{
        email: 'test@example.com',
        password: 'password',
        password_confirmation: 'password',
        name: 'Foo Bar',
        address: 'Tokyo-to'
      }}

    it 'should create customer without webpay_token' do
      expect { post :create, customer: basic_params }.to change(Customer, :count).by(1)
      expect(Customer.last.webpay_customer_id).to eq nil
    end

    it 'should create customer with webpay_token' do
      token_id = 'tok_XXXXXXXXX'
      params = { card: token_id, email: basic_params[:email], description: basic_params[:name] }
      dummy_customer = customer_from(params)
      expect(WebPay::Customer).to receive(:create).with(params).and_return(dummy_customer)
      expect { post :create, customer: basic_params.merge('webpay_token' => token_id) }.to change(Customer, :count).by(1)
      expect(Customer.last.webpay_customer_id).to eq dummy_customer.id
    end

    context 'if WebPay responds error' do
      let(:token_id) { 'tok_XXXXXXXXX' }

      before do
        expect(WebPay::Customer).to receive(:create)
          .with(card: token_id, email: basic_params[:email], description: basic_params[:name])
          .and_raise(card_error)
      end

      def do_request
        post :create, customer: basic_params.merge('webpay_token' => token_id)
      end

      it 'should create customer without webpay_customer_id' do
        expect { do_request }.to change(Customer, :count).by(1)
        expect(Customer.last.webpay_customer_id).to eq nil
      end

      it 'should redirect to customer edit page' do
        do_request
        expect(response).to redirect_to(edit_customer_registration_path)
      end

      it 'should set notice with error message' do
        do_request
        expect(flash[:notice]).to eq I18n.t('devise.registrations.customer.signed_up_but_webpay_error', message: "This card cannot be used.")
      end
    end
  end

  describe '#update' do
    let(:new_email) { 'yyy@example.com' }
    let(:password) { 'password' }
    let(:customer) { Fabricate(:customer, password: password) }
    let(:basic_params) { { current_password: password, email: new_email } }
    before { sign_in customer }

    context 'when the customer has no webpay_customer_id' do
      it 'should update the customer' do
        patch :update, customer: basic_params
        customer.reload
        expect(customer.email).to eq new_email
        expect(customer.webpay_customer_id).to eq nil
      end

      it 'should set webpay_customer_id of the customer' do
        token_id = 'tok_XXXXXXXXX'
        params = { card: token_id, email: new_email, description: customer.name }
        dummy_customer = customer_from(params)
        expect(WebPay::Customer).to receive(:create).with(params).and_return(dummy_customer)
        patch :update, customer: basic_params.merge(webpay_token: token_id)
        customer.reload
        expect(customer.email).to eq new_email
        expect(customer.webpay_customer_id).to eq dummy_customer.id
      end
    end

    context 'when the customer has webpay_customer_id' do
      let(:original_id) { 'cus_XXXXXXXXX' }
      before { customer.update_attributes!(webpay_customer_id: original_id) }

      it 'should update email field of WebPay customer model if no webpay_token' do
        retrieved = double('WebPay::Customer', id: original_id)
        expect(WebPay::Customer).to receive(:retrieve)
          .with(original_id)
          .and_return(retrieved)
        expect(retrieved).to receive(:email=).with(new_email)
        expect(retrieved).to receive(:description=).with(customer.name)
        expect(retrieved).to receive(:save).and_return(retrieved)

        patch :update, customer: basic_params
        customer.reload
        expect(customer.email).to eq new_email
        expect(customer.webpay_customer_id).to eq original_id
      end

      it 'should update email and card field of WebPay customer model with webpay_token' do
        token_id = 'tok_XXXXXXXXX'
        retrieved = double('WebPay::Customer', id: original_id)
        expect(WebPay::Customer).to receive(:retrieve)
          .with(original_id)
          .and_return(retrieved)
        expect(retrieved).to receive(:card=).with(token_id)
        expect(retrieved).to receive(:email=).with(new_email)
        expect(retrieved).to receive(:description=).with(customer.name)
        expect(retrieved).to receive(:save).and_return(retrieved)

        patch :update, customer: basic_params.merge(webpay_token: token_id)
        customer.reload
        expect(customer.email).to eq new_email
        expect(customer.webpay_customer_id).to eq original_id
      end
    end

    context 'if WebPay responds error' do
      let(:token_id) { 'tok_XXXXXXXXX' }

      before do
        expect(WebPay::Customer).to receive(:create)
          .with(card: token_id, email: new_email, description: customer.name)
          .and_raise(card_error)
      end

      def do_request
        patch :update, customer: basic_params.merge('webpay_token' => token_id)
      end

      it 'should update email' do
        do_request
        expect(customer.reload.email).to eq new_email
      end

      it 'should redirect to customer edit page' do
        do_request
        expect(response).to redirect_to(edit_customer_registration_path)
      end

      it 'should set notice with error message' do
        do_request
        expect(flash[:notice]).to eq I18n.t('devise.registrations.customer.updated_but_webpay_error', message: "This card cannot be used.")
      end
    end
  end
end
