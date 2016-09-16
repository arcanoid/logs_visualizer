require 'logs_visualizer/version'

module LogsVisualizer
  def self.produce_graph(string_input, graph_name = nil, options = {})
    if string_input.present?
      g = GraphViz::new( :G, :type => :digraph )
      g[:rankdir] ='LR'

      data = populate_data string_input, options
      populate_graph g, data, graph_name
    end
  end

  #########
  protected
  #########

  def self.populate_data(logs_text, options = {})
    data = { :nodes => [] }

    logs_text.split('Started ').each do |action|
      if action.present? && action != ""
        action_parsed = /(?<action>.*) for/.match(action)[:action]
        rendered_partials = []
        service_requests = []
        service_times = []
        compiled_assets = []
        sql_insertions = []
        sql_selections = []
        sql_updates = []
        serializers = []

        unless /.*\"\/assets.*/.match(action_parsed)
          action.split("\r\n").each do |log_line|
            partial_in_line = /Rendered (?<partial>(\S)*).*\((?<time>(\S)*)ms/.match(log_line)
            service_request_in_line = /\[httplog\] Sending: (?<service>.*)/.match(log_line)
            service_time_in_line = /\[httplog\] Benchmark: (?<time>\S*)/.match(log_line)
            compiled_asset_in_line = /Compiled (?<asset>(\S)*).*\((?<time>\S*)ms\)/.match(log_line)
            sql_insertion_in_line = /SQL.*\((?<time>\S*)ms\).*INSERT INTO (?<table>(\S)*)/.match(log_line)
            sql_select_in_line = /\((?<time>\S*)ms\).*SELECT .* FROM (?<table>(\S)*)/.match(log_line)
            sql_update_in_line = /\((?<time>\S*)ms\).*UPDATE (?<table>(\S)*)/.match(log_line)
            serializer_in_line = /\[active_model_serializers\] Rendered (?<serializer>\S*) with .* \((?<time>\S*)ms\)/.match(log_line)

            if partial_in_line.present? && (options[:rendered_partials] == true || options[:all] == true)
              rendered_partials << { :partial => partial_in_line[:partial], :time => partial_in_line[:time].to_f }
            end

            if service_time_in_line.present? && (options[:service_requests] == true || options[:all] == true)
              service_times << service_time_in_line[:time].to_f
            end

            if service_request_in_line.present? && (options[:service_requests] == true || options[:all] == true)
              service_requests << service_request_in_line[:service]
            end

            if compiled_asset_in_line.present? && (options[:compiled_assets] == true || options[:all] == true)
              compiled_assets << { :asset => compiled_asset_in_line[:asset], :time => compiled_asset_in_line[:time].to_f }
            end

            if sql_insertion_in_line.present? && (options[:sql_visualization] == true || options[:all] == true)
              sql_insertions <<  { :table => sql_insertion_in_line[:table], :time => sql_insertion_in_line[:time].to_f }
            end

            if sql_select_in_line.present? && (options[:sql_visualization] == true || options[:all] == true)
              sql_selections << { :table => sql_select_in_line[:table], :time => sql_select_in_line[:time].to_f }
            end

            if sql_update_in_line.present? && (options[:sql_visualization] == true || options[:all] == true)
              sql_updates << { :table => sql_update_in_line[:table], :time => sql_update_in_line[:time].to_f }
            end

            if serializer_in_line.present? && (options[:serializers] == true || options[:all] == true)
              serializers << { :serializer => serializer_in_line[:serializer], :time => serializer_in_line[:time].to_f }
            end
          end

          controller_processing_request = /Processing by (?<controller>.*) as/.match(action)[:controller]
          redirect_to_url = /Redirected to (?<redirect_url>(\S)*)/.match(action)

          if data[:nodes].size > 0 && (data[:nodes].map { |node| node[:label] }.include? action_parsed)
            data[:nodes].map { |node| node[:size] += 1 if node[:label] == action_parsed }
          else
            services = []

            service_requests.each_with_index do |service, index|
              services << { :service => service, :time => service_times[index] }
            end

            data[:nodes] << {
                :size => 1,
                :label => action_parsed,
                :controller => controller_processing_request,
                :redirect => (URI(redirect_to_url[:redirect_url]) if redirect_to_url.present? ),
                :rendered_partials => rendered_partials.group_by { |x| x[:partial] },
                :service_requests => services,
                :compiled_assets => compiled_assets.group_by { |x| x[:asset] },
                :sql_insertions => sql_insertions.group_by { |x| x[:table] },
                :sql_selections => sql_selections.group_by { |x| x[:table] },
                :sql_updates => sql_updates.group_by { |x| x[:table] },
                :serializers => serializers.group_by { |x| x[:serializer] },
            }
          end
        end
      end
    end

    data
  end

  def self.populate_graph(graph, data, graph_name = nil)
    if data[:nodes].present?
      data[:nodes].each do |node|
        node[:graph_node] = graph.add_nodes(node[:label], :label => "<<b>#{node[:label].gsub('&', '%26')}</b><br/><i>#{node[:controller]}</i>>")

        maximum_rendered_time = node[:rendered_partials].map { |partial, partials_array| partials_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.max
        maximum_sql_insertion_time = node[:sql_insertions].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.max
        maximum_asset_compilation_time = node[:compiled_assets].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.max
        maximum_sql_selection_time = node[:sql_selections].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.max
        maximum_sql_update_time = node[:sql_updates].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.max
        maximum_service_time = node[:service_requests].group_by { |x| x[:service] }.map { |service, services_array| (services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2) }.max
        maximum_serializer_time = node[:serializers].map { |array_name, names_array| (names_array.inject(0){|sum,x| sum + x[:time] }).round(2) }.max

        minimum_rendered_time = node[:rendered_partials].map { |partial, partials_array| partials_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.min
        minimum_sql_insertion_time = node[:sql_insertions].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.min
        minimum_asset_compilation_time = node[:compiled_assets].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.min
        minimum_sql_selection_time = node[:sql_selections].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.min
        minimum_sql_update_time = node[:sql_updates].map { |array_name, names_array| names_array.inject(0){|sum,x| sum + x[:time] }.round(2) }.min
        minimum_service_time = node[:service_requests].group_by { |x| x[:service] }.map { |service, services_array| (services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2) }.min
        minimum_serializer_time = node[:serializers].map { |service, services_array| (services_array.inject(0){|sum,x| sum + x[:time] }).round(2) }.min

        node[:rendered_partials].each do |partial, partials_array|
          partial_node = graph.add_nodes(partial, :shape => :component)
          total_time = partials_array.inject(0){|sum,x| sum + x[:time] }.round(2)
          if maximum_rendered_time == total_time
            graph.add_edges( node[:graph_node], partial_node, :label => "<<i>Renders<br/>(#{partials_array.size} times)<br/>in <b>#{partials_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif minimum_rendered_time == total_time
            graph.add_edges( node[:graph_node], partial_node, :label => "<<i>Renders<br/>(#{partials_array.size} times)<br/>in <b>#{partials_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( node[:graph_node], partial_node, :label => "<<i>Renders<br/>(#{partials_array.size} times)<br/>in #{partials_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</i>>")
          end
        end

        if node[:redirect].present?
          graph.add_edges( node[:graph_node], "GET \"#{node[:redirect].path}\"", :label => "<<i>Redirects to</i>>")
        end

        node[:compiled_assets].each do |asset, assets_array|
          asset_node = graph.add_nodes(asset, :shape => :folder)
          total_time = assets_array.inject(0){|sum,x| sum + x[:time] }.round(2)
          if maximum_asset_compilation_time == total_time
            graph.add_edges( node[:graph_node], asset_node, :label => "<<i>Compiles asset<br/>(#{assets_array.size} times)<br/>in <b>#{assets_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif minimum_asset_compilation_time == total_time
            graph.add_edges( node[:graph_node], asset_node, :label => "<<i>Compiles asset<br/>(#{assets_array.size} times)<br/>in <b>#{assets_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( node[:graph_node], asset_node, :label => "<<i>Compiles asset<br/>(#{assets_array.size} times)<br/>in #{assets_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</i>>")
          end
        end

        node[:serializers].each do |name, serializers_array|
          graph_node = graph.add_nodes(name, :shape => :msquare)
          total_time = serializers_array.inject(0){|sum,x| sum + x[:time] }.round(2)

          if maximum_serializer_time == total_time
            graph.add_edges( node[:graph_node], graph_node, :label => "<<i>Serializes through<br/>(#{serializers_array.size} times)<br/>in <b>#{serializers_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif minimum_serializer_time == total_time
            graph.add_edges( node[:graph_node], graph_node, :label => "<<i>Serializes through<br/>(#{serializers_array.size} times)<br/>in <b>#{serializers_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( node[:graph_node], graph_node, :label => "<<i>Serializes through<br/>(#{serializers_array.size} times)<br/>in #{serializers_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</i>>")
          end
        end

        node[:sql_insertions].each do |array_name, names_array|
          array_node = graph.add_nodes(array_name, :shape => :box3d)
          total_time = names_array.inject(0){|sum,x| sum + x[:time] }.round(2)
          if maximum_sql_insertion_time == total_time
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Inserts into<br/>(#{names_array.size} times)<br/>in <b>#{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif minimum_sql_insertion_time == total_time
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Inserts into<br/>(#{names_array.size} times)<br/>in <b>#{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Inserts into<br/>(#{names_array.size} times)<br/>in #{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</i>>")
          end
        end

        node[:sql_selections].each do |array_name, names_array|
          array_node = graph.add_nodes(array_name, :shape => :box3d)
          total_time = names_array.inject(0){|sum,x| sum + x[:time] }.round(2)
          if maximum_sql_selection_time == total_time
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Selects from<br/>(#{names_array.size} times)<br/>in <b>#{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif minimum_sql_selection_time == total_time
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Selects from<br/>(#{names_array.size} times)<br/>in <b>#{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Selects from<br/>(#{names_array.size} times)<br/>in #{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</i>>")
          end
        end

        node[:sql_updates].each do |array_name, names_array|
          array_node = graph.add_nodes(array_name, :shape => :box3d)
          total_time = names_array.inject(0){|sum,x| sum + x[:time] }.round(2)
          if maximum_sql_update_time == total_time
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Updates<br/>(#{names_array.size} times)<br/>in <b>#{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif minimum_sql_update_time == total_time
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Updates<br/>(#{names_array.size} times)<br/>in <b>#{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( node[:graph_node], array_node, :label => "<<i>Updates<br/>(#{names_array.size} times)<br/>in #{names_array.inject(0){|sum,x| sum + x[:time] }.round(2)}ms</i>>")
          end
        end

        node[:service_requests].
            map { |service| {:service => URI(service[:service].split(' ')[1]).host, :time => service[:time]} }.
            group_by { |x| x[:service] }.
            each do |service, services_array|

          service_node = graph.add_nodes(service, :shape => :note)
          graph.add_edges( node[:graph_node], service_node, :label => "<<i>Requests<br/>(#{services_array.size} times)<br/>in #{(services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2)}ms</i>>")
        end

        node[:service_requests].group_by { |x| x[:service] }.each do |service, services_array|
          service_split = service.split(' ')
          full_service_node = graph.add_nodes("#{service_split[0]} #{[URI(service.split(' ')[1]).path, URI(service.split(' ')[1]).query.presence].reject { |x| x.blank? }.join('?')}", :shape => :note)
          total_time = (services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2)

          if total_time == maximum_service_time
            graph.add_edges( URI(service.split(' ')[1]).host, full_service_node, :label => "<<i>Includes requests to<br/>(#{services_array.size} times)<br/>in <b>#{(services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2)}ms</b></i>>", :color => 'red', :fontcolor => 'red')
          elsif total_time == minimum_service_time
            graph.add_edges( URI(service.split(' ')[1]).host, full_service_node, :label => "<<i>Includes requests to<br/>(#{services_array.size} times)<br/>in <b>#{(services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2)}ms</b></i>>", :color => 'darkgreen', :fontcolor => 'darkgreen')
          else
            graph.add_edges( URI(service.split(' ')[1]).host, full_service_node, :label => "<<i>Includes requests to<br/>(#{services_array.size} times)<br/>in #{(services_array.inject(0){|sum,x| sum + x[:time] } * 1000).round(2)}ms</i>>")
          end
        end
      end

      directory_name = 'app/assets/images/graphs'
      FileUtils.mkdir_p('app') unless File.directory?('app')
      FileUtils.mkdir_p('app/assets') unless File.directory?('app/assets')
      FileUtils.mkdir_p('app/assets/images') unless File.directory?('app/assets/images')
      FileUtils.mkdir_p(directory_name) unless File.directory?(directory_name)
      graph.output(:png => "#{directory_name}/#{graph_name.present? ? graph_name : "graph_#{DateTime.now.strftime('%H%M%S%L')}" }.png" )
    end
  end
end
