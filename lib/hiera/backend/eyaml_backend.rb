class Hiera
    module Backend
        class Eyaml_backend

            def initialize
                require 'openssl'
                require 'base64'
            end

            def lookup(key, scope, order_override, resolution_type)
    
                debug("Lookup called for key #{key}")
                answer = nil
    
                Backend.datasources(scope, order_override) do |source|
                    eyaml_file = Backend.datafile(:eyaml, scope, source, "eyaml") || next

                    debug("Processing datasource: #{eyaml_file}")

                    data = YAML.load(File.read( eyaml_file ))

                    next if !data
                    next if data.empty?
                    debug ("Data contains valid YAML")

                    next unless data.include?(key)
                    debug ("Key #{key} found in YAML document")

                    parsed_answer = parse_answer(data[key], scope)

                    begin
                        case resolution_type
                        when :array
                            debug("Appending answer array")
                            raise Exception, "Hiera type mismatch: expected Array and got #{parsed_answer.class}" unless parsed_answer.kind_of? Array or parsed_answer.kind_of? String
                            answer ||= []
                            answer << parsed_answer
                        when :hash
                            debug("Merging answer hash")
                            raise Exception, "Hiera type mismatch: expected Hash and got #{parsed_answer.class}" unless parsed_answer.kind_of? Hash
                            answer ||= {}
                            answer = parsed_answer.merge answer
                        else
                            debug("Assigning answer variable")
                            answer = parsed_answer
                            break
                        end
                    rescue NoMethodError
                        raise Exception, "Resolution type is #{resolution_type} but parsed_answer is a #{parsed_answer.class}"
                    end
                end
    
                return answer
            end

            def parse_answer(data, scope, extra_data={})
                if data.is_a?(Numeric) or data.is_a?(TrueClass) or data.is_a?(FalseClass)
                    # Can't be encrypted
                    return data
                elsif data.is_a?(String)
                    parsed_string = Backend.parse_string(data, scope)
                    return decrypt(parsed_string, scope)
                elsif data.is_a?(Hash)
                    answer = {}
                    data.each_pair do |key, val|
                        answer[key] = parse_answer(val, scope, extra_data)
                    end
                    return answer
                elsif data.is_a?(Array)
                    answer = []
                    data.each do |item|
                        answer << parse_answer(item, scope, extra_data)
                    end
                    return answer
                end
            end

            def decrypt(value, scope)

                if is_encrypted(value)

                    # remove enclosing 'ENC[]'
                    ciphertext = value[4..-2]
                    ciphertext_decoded = Base64.decode64(ciphertext)

                    debug("Decrypting value")

                    private_key_path = Backend.parse_string(Config[:eyaml][:private_key], scope) || '/etc/hiera/keys/private_key.pem'
                    public_key_path = Backend.parse_string(Config[:eyaml][:public_key], scope) || '/etc/hiera/keys/public_key.pem'

                    private_key_pem = File.read( private_key_path )
                    private_key = OpenSSL::PKey::RSA.new( private_key_pem )

                    public_key_pem = File.read( public_key_path )
                    public_key = OpenSSL::X509::Certificate.new( public_key_pem )

                    pkcs7 = OpenSSL::PKCS7.new( ciphertext_decoded )

                    begin
                      plaintext = pkcs7.decrypt(private_key, public_key)
                    rescue
                      raise Exception, "Hiera eyaml backend: Unable to decrypt hiera data. Do the keys match and are they the same as those used to encrypt?"
                    end
        
                    return plaintext
    
                else
                    return value
                end
            end

            def is_encrypted(value)
                if value.start_with?('ENC[')
                    return true
                else
                    return false
                end
            end

            def debug(msg)
                Hiera.debug("[eyaml_backend]: #{msg}")
            end

            def warn(msg)
                Hiera.warn("[eyaml_backend]:  #{msg}")
            end
        end
    end
end
