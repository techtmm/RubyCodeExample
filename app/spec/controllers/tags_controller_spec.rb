require 'rails_helper'

describe TagsController, type: :controller do
  let(:company) { create(:company, :with_admin) }
  let(:user) { company.admins.first }

  before do
    sign_in user
  end

  shared_examples 'not allowed from other company' do
    context 'when requested from other company' do
      let(:other_company) { create(:company) }
      let(:tag) { create(:tag, company: other_company) }

      it 'responds with 404 status code' do
        expect(response.status).to eq(404)
      end
    end
  end

  shared_examples 'allowed as JSON' do
    it 'responds with 200 status code' do
      expect(response.status).to eq(200)
    end

    it 'responds with json content type' do
      expect(response.header['Content-Type']).to include('application/json')
    end
  end

  shared_examples 'not allowed as HTML' do
    context 'when requested as HTML' do
      let(:format) { :html }

      it 'responds with 406 status code' do
        expect(response.status).to eq(406)
      end
    end
  end

  describe 'GET #index' do
    before do
      get :index, format: format
    end

    context 'when requested as JSON' do
      let(:format) { :json }

      include_examples 'allowed as JSON'
    end

    include_examples 'not allowed as HTML'
  end

  describe 'GET #show' do
    let(:tag) { create(:tag, company: company) }

    before do
      get :show, params: {id: tag.id}, format: format
    end

    context 'when requested as JSON' do
      let(:format) { :json }

      include_examples 'allowed as JSON'
      include_examples 'not allowed from other company'
    end

    include_examples 'not allowed as HTML'
  end

  describe 'POST #create' do
    let(:tag) { attributes_for(:tag, company: company) }
    let(:params) { {tag: tag, format: :json} }

    before do
      post :create, params: params
    end

    context 'when record is valid' do
      it 'responds with 201 status code' do
        expect(response.status).to eq(201)
      end

      it 'responds with new record' do
        expect(json['tag']).to eq(tag[:tag])
      end
    end

    context 'when record is not valid' do
      let(:tag) { attributes_for(:tag, tag: nil, company: company) }

      it 'responds with 422 status code' do
        expect(response.status).to eq(422)
      end
    end
  end

  describe 'PUT #update' do
    let(:tag) { create(:tag, company: company) }
    let(:params) { {id: tag.id, tag: tag_attributes, format: :json} }

    before do
      put :update, params: params
    end

    context 'when record is valid' do
      let(:tag_attributes) { {tag: 'my new tag'} }

      it 'responds with 204 status code' do
        expect(response.status).to eq(204)
      end

      it 'does not respond with updated record' do
        expect(response.body).to be_empty
      end
    end

    context 'when record is not valid' do
      let(:tag_attributes) { {tag: nil} }

      it 'responds with 422 status code' do
        expect(response.status).to eq(422)
      end
    end
  end

  describe 'DELETE #destroy' do
    let(:tag) { create(:tag, company: company) }

    it 'does not have destroy method' do
      expect { delete :destroy, params: {id: tag.id}, format: :json }.to raise_error(AbstractController::ActionNotFound)
    end
  end
end
