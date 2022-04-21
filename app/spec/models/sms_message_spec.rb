require 'rails_helper'

describe SmsMessage, type: :model do
  let(:company) { create(:company_with_sms_module, :with_admin) }
  let(:sms_settings) { create(:company_sms_settings, company: company) }

  context 'after creation' do
    let(:phone_number) { 'NDA' }
    let(:message) { 'Hello world' }
    let(:from) { 'NDA' }

    subject(:sms_message) { described_class.new(company: company, to: phone_number, text: message, from: from) }

    context 'when success' do
      let(:success_response) {
        {
          success: true,
          code: 100,
          message: 'NDA',
          info: 'Does not matter'
        }
      }

      before do
        allow_any_instance_of(SmsSender).to receive(:send_sms).and_return(nil)
        allow_any_instance_of(SmsSender).to receive(:formatted_response).and_return(success_response)
        sms_settings
      end

      it 'stores success flag' do
        expect {
          sms_message.save
        }.to change(sms_message, :success).from(nil).to(success_response[:success])
      end

      it 'stores response code' do
        expect {
          sms_message.save
        }.to change(sms_message, :response_code).from(nil).to(success_response[:code])
      end

      it 'stores response message' do
        expect {
          sms_message.save
        }.to change(sms_message, :response_message).from(nil).to(success_response[:message])
      end

      it 'stores response info' do
        expect {
          sms_message.save
        }.to change(sms_message, :response_info).from(nil).to(success_response[:info])
      end
    end
  end
end
