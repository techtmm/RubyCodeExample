# frozen_string_literal: true

class TrafficReportQuery
  attr_reader :time_range

  def initialize(time_range)
    @time_range = time_range
  end

  def execute
    [
      incoming_traffics,
      outgoing_traffics,
      mobile3rd_party_traffics
    ].flatten.group_by(&:company_id)
  end

  def count
    {
      incoming: incoming_traffics.sum(&:requests_count),
      outgoing: outgoing_traffics.sum(&:requests_count),
      mobile_3rd_party: mobile3rd_party_traffics.sum(&:requests_count)
    }
  end

  private

  def outgoing_traffics
    @outgoing_traffics ||= OutgoingTraffic.select(outgoing_select_statement)
                                          .where(created_at: time_range)
                                          .group(:company_id, :provider_type)
                                          .order(:company_id)
                                          .includes(:company).to_a
  end

  def incoming_traffics
    @incoming_traffics ||= Traffic.select(incoming_select_statement)
                                  .where(created_at: time_range)
                                  .group(:app_code_id, :company_id)
                                  .order(:company_id)
                                  .includes(:company, :app_code, :project).to_a
  end

  def mobile3rd_party_traffics
    @mobile3rd_party_traffics ||= Mobile3rdPartyTraffic.select(mobile3rd_party_select_statement)
                                                       .where(created_at: time_range)
                                                       .group(:company_id, :provider_type)
                                                       .order(:company_id)
                                                       .includes(:company).to_a
  end

  def incoming_select_statement
    <<~INCOMING_SELECT_STATEMENT.gsub(/\n/, ' ')
      project_id,
      app_code_id,
      company_id,
      COUNT(*) AS requests_count,
      (SUM(request_length) + SUM(response_length)) AS sum_content_length
    INCOMING_SELECT_STATEMENT
  end

  def outgoing_select_statement
    <<~OUTGOING_SELECT_STATEMENT.gsub(/\n/, ' ')
      company_id,
      provider_type,
      COUNT(*) AS requests_count,
      (SUM(request_length) + SUM(response_length)) AS sum_content_length
    OUTGOING_SELECT_STATEMENT
  end

  def mobile3rd_party_select_statement
    <<~MOBILE3RD_PARTY_SELECT_STATEMENT.gsub(/\n/, ' ')
      company_id,
      provider_type,
      COUNT(*) AS requests_count,
      (SUM(request_length) + SUM(response_length)) AS sum_content_length
    MOBILE3RD_PARTY_SELECT_STATEMENT
  end
end
