module RegexpCrawler
  class Crawler
    attr_accessor :start_page, :continue_regexp, :named_captures, :model, :save_method, :headers, :encoding, :need_parse

    def initialize(options = {})
      @start_page = options[:start_page]
      @continue_regexp = options[:continue_regexp]
      @capture_regexp = options[:capture_regexp]
      @named_captures = options[:named_captures]
      @model = options[:model]
      @save_method = options[:save_method]
      @headers = options[:headers]
      @encoding = options[:encoding]
      @need_parse = options[:need_parse]
    end

    def capture_regexp=(regexp)
      @capture_regexp = Regexp.new(regexp.source, regexp.options | Regexp::MULTILINE)
    end

    def start
      @results = []
      @captured_pages = []
      @pages = [URI.parse(@start_page)]
      while !@pages.empty? and !@stop
        uri = @pages.shift
        @captured_pages << uri
        parse_page(uri)
      end
      @results
    end

    private
      def parse_page(uri)
        response = Net::HTTP.get_response_with_headers(uri, @headers)
        parse_response(response, uri)
      end

      def continue_uri(uri, page)
        if page.start_with?(uri.scheme)
          URI.parse(page)
        elsif page.start_with?('/')
          URI.join(uri.scheme + '://' + uri.host, page)
        else
          URI.parse(uri.to_s.split('/')[0..-2].join('/') + '/' + page)
        end
      end

      def parse_response(response, uri)
        response_body = encoding.nil? ? response.body : Iconv.iconv("UTF-8//IGNORE", "#{encoding}//IGNORE", response.body).first
        if response.is_a? Net::HTTPSuccess
          if continue_regexp
            response_body.scan(continue_regexp).each do |page|
              page = page.compact.first if page.is_a? Array
              continue_uri = continue_uri(uri, page)
              @pages << continue_uri unless @captured_pages.include?(continue_uri) or @pages.include?(continue_uri)
            end 
          end
          if @need_parse.nil? or @need_parse.call(uri, response_body)
            md = @capture_regexp.match(response_body)
            if md
              captures = md.captures
              result = {}
              captures.each_index do |i|
                result[named_captures[i].to_sym] = captures[i]
              end
              if @save_method
                ret = @save_method.call(result, uri.to_s)
                @stop = true if ret == false
              else
                @results << {@model.downcase.to_sym => result, :page => uri.to_s}
              end
            end
          end
        elsif response.is_a? Net::HTTPRedirection
          parse_page(URI.parse(response['location']))
        else
          # do nothing
        end
      end
  end
end
