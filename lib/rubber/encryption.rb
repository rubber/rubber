require 'openssl'
require 'base64'

module Rubber
  module Encryption
    
    def cipher_algorithm
      OpenSSL::Cipher.new("AES-256-CBC")
    end
    
    def cipher_digest
      OpenSSL::Digest.new("SHA256")
    end
    
    def generate_encrypt_key
      OpenSSL::Digest.hexdigest('md5', rand.to_s)
    end
    
    def encrypt(payload, secret)
      cipher = cipher_algorithm

      cipher.encrypt
      cipher.pkcs5_keyivgen(cipher_digest.hexdigest(secret))
      
      encrypted_data = cipher.update(payload) + cipher.final
      encoded_encrypted_data = Base64.encode64(encrypted_data)
      
      return encoded_encrypted_data
    end
    
    def decrypt(encoded_encrypted_data, secret)
      cipher = cipher_algorithm

      cipher.decrypt
      cipher.pkcs5_keyivgen(cipher_digest.hexdigest(secret))
      
      encrypted_data = Base64.decode64(encoded_encrypted_data)
      payload = cipher.update(encrypted_data) + cipher.final
      
      return payload
    end

    extend self
    
  end
end