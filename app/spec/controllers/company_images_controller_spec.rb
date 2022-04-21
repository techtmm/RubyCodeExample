require 'rails_helper'

describe CompanyImagesController, type: :controller do
  let(:params) do
    { company_id: company.id }
  end

  context 'when not admin user' do
    let(:company) { create(:company, :with_admin, time_zone: 'NDA') }
    let(:normal_user) { create(:user, company: company, accepted_privacy_policy: true) }

    before do
      sign_in normal_user
    end

    context 'it redirects' do
      before do
        expect(controller).to receive(:admin_required) { controller.redirect_to root_path }
      end

      it { get :show, params: params }
      it { post :create, params: params }
      it { put :update, params: params }
      it { delete :destroy, params: params }
    end
  end

  context 'when company without module activated' do
    let(:company) { create(:company, time_zone: 'NDA') }
    let(:user) { create(:admin, company: company, accepted_privacy_policy: true) }

    before do
      sign_in user
    end

    context 'it redirects' do
      before do
        expect(controller).to receive(:check_module_available) { controller.redirect_to root_path }
      end

      it { get :show, params: params }
      it { post :create, params: params }
      it { put :update, params: params }
      it { delete :destroy, params: params }
    end
  end

  context 'when access granted' do
    let(:company) { create(:company_with_campaign_management_module, time_zone: 'NDA') }
    let(:user) { create(:admin, company: company, accepted_privacy_policy: true) }

    before do
      sign_in user
    end

    describe '#show' do
      it 'renders view' do
        get :show, params: params
        expect(response.status).to eq(200)
        expect(response).to render_template(:show)
      end
    end

    describe '#create' do
      context 'when created successfully' do
        it 'responds with 200 status code' do
          allow_any_instance_of(CompanyImage).to receive(:save).and_return(true)
          post :create, params: params
          expect(response.status).to eq(200)
        end
      end

      context 'when creation fails' do
        it 'responds with errors' do
          allow_any_instance_of(CompanyImage).to receive(:save).and_return(false)
          post :create, params: params
          expect(response.status).to eq(422)
          expect(response).to match_response_schema('errors_with_full_messages')
        end
      end
    end

    describe '#update' do
      context 'when update' do
        before do
          company.company_image = build(:company_image, company: company)
        end

        context 'successfully' do
          it 'responds with 200 status code' do
            allow_any_instance_of(CompanyImage).to receive(:update).and_return(true)
            put :update, params: params
            expect(response.status).to eq(200)
          end
        end

        context 'fails' do
          it 'responds with errors' do
            allow_any_instance_of(CompanyImage).to receive(:update).and_return(false)
            put :update, params: params
            expect(response.status).to eq(422)
            expect(response).to match_response_schema('errors_with_full_messages')
          end
        end
      end

      context 'when item not found on update' do
        it 'responds with errors' do
          put :update, params: params
          expect(response.status).to eq(404)
          expect(response).to match_response_schema('errors_with_full_messages')
        end
      end
    end

    describe '#destroy' do
      it 'redirects to company image page' do
        delete :destroy, params: params
        expect(controller).to redirect_to company_company_image_path(company)
      end
    end
  end
end
