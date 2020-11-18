require 'puppet'

require_relative '../../puppet_x/relay'

Puppet::Reports.register_report(:relay) do
  desc 'Submit reports to a Relay trigger'

  def process
    settings = PuppetX::Relay::Util::DefaultSettings.new
    settings = PuppetX::Relay::Util::FileSettings.new(settings)

    if settings[:relay_trigger_token].nil?
      Puppet.warning(_('No Relay trigger tokens defined, not forwarding any reports to Relay service'))
      return
    end

    reports = prepare_reports
    return if reports.empty?

    trigger_tokens = [*settings[:relay_trigger_token]]
    trigger_tokens.each_with_index do |trigger_token, i|
      Puppet.notice(_('Submitting batch of %{n} report(s) to Relay service at %{endpoint}, trigger index %{i}') % { n: reports.length, endpoint: settings[:relay_api_url], i: i })

      relay_api = PuppetX::Relay::Util::HTTP::RelayAPI.new(settings[:relay_api_url], trigger_token)
      relay_api.emit_event(reports: reports)
    end
  rescue StandardError => e
    Puppet.err(_('Failed to submit reports to Relay service: %{e}') % { e: e })
  end

  def facts
    Puppet::Node::Facts.indirection.find(host).values
  end

  def prepare_reports
    # Do not report unless something has changed.
    return [] if status == 'unchanged' && !noop_pending

    # TODO: Collect multiple reports and batch them.
    [{
      host: host,
      noop: noop,
      facts: facts,
      status: status,
      time: time.iso8601,
      configuration_version: configuration_version,
      transaction_uuid: transaction_uuid,
      code_id: code_id,
      summary: summary,
      resource_statuses: resource_statuses
        .select { |_key, value| !value.skipped && (value.change_count > 0 || value.out_of_sync_count > 0) }
        .transform_values do |value|
          {
            resource_type: value.resource_type,
            title: value.title,
            change_count: value.change_count,
            out_of_sync_count: value.out_of_sync_count,
          }
        end,
    }]
  end
end
