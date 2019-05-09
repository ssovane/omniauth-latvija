module OmniAuth::Strategies
  class Latvija
    class Response
      ASSERTION = 'urn:oasis:names:tc:SAML:1.0:assertion'.freeze

      attr_accessor :options, :response

      def initialize(response, **options)
        raise ArgumentError, 'Response cannot be nil' if response.nil?
        @options  = options
        @response = response
        @document = OmniAuth::Strategies::Latvija::SignedDocument.new(response, private_key: options[:private_key])
      end

      def validate!
        @document.validate!(fingerprint) && validate_timestamps!
      end

      def xml
        @document.nokogiri_xml
      end

      def authentication_method
        @authentication_method ||= begin
          xml.xpath('//saml:AuthenticationStatement', saml: ASSERTION).attribute('AuthenticationMethod')
        end
      end

      # A hash of all the attributes with the response.
      # Assuming there is only one value for each key
      def attributes
        @attributes ||= begin
          attrs = {
            'not_valid_before' => not_valid_before,
            'not_valid_on_or_after' => not_valid_on_or_after
          }

          stmt_elements = xml.xpath('//a:Attribute', a: ASSERTION)
          return attrs if stmt_elements.nil?

          stmt_elements.each_with_object(attrs) do |element, result|
            name  = element.attribute('AttributeName').value
            value = element.text

            result[name] = value
          end
        end
      end

      private

      def fingerprint
        cert = OpenSSL::X509::Certificate.new(options[:certificate])
        Digest::SHA1.hexdigest(cert.to_der).upcase.scan(/../).join(':')
      end

      def conditions_tag
        @conditions_tag ||= xml.xpath('//saml:Conditions', saml: ASSERTION)
      end

      def not_valid_before
        @not_valid_before ||= conditions_tag.attribute('NotBefore').value
      end

      def not_valid_on_or_after
        @not_valid_on_or_after ||= conditions_tag.attribute('NotOnOrAfter').value
      end

      def validate_timestamps!
        current_timestamp = Time.current

        already_valid = Time.parse(not_valid_before) <= current_timestamp
        still_valid = current_timestamp < Time.parse(not_valid_on_or_after)

        if already_valid && still_valid
          true
        else
          raise ValidationError, 'Timestamp error'
        end
      end
    end
  end
end
