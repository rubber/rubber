require 'openssl'
require 'digest/sha2'
require 'base64'

module Rubber
  module Encryption
    
    def generate_encrypt_key
      key = rand.to_s
      iv = rand.to_s
      encode_encrypt_key(key, iv)
    end
    
    def decode_encrypt_key(key)
      data = Base64.strict_decode64(key)
      parts = data.split(":")
      raise "Invalid encryption key" if parts.size != 2 
      return *parts
    end

    def encode_encrypt_key(key, iv)
      key = Base64.strict_encode64("#{key}:#{iv}")
      return key
    end
    
    def encrypt(payload, secret)
      sha256 = Digest::SHA2.new(256)
      aes = OpenSSL::Cipher.new("AES-256-CFB")
      
      key, iv = decode_encrypt_key(secret)
      key = sha256.digest(key)
      
      aes.encrypt
      aes.key = key
      aes.iv = iv
      encrypted_data = aes.update(payload) + aes.final
      encoded_encrypted_data = Base64.encode64(encrypted_data)
      
      return encoded_encrypted_data
    end
    
    def decrypt(encoded_encrypted_data, secret)
      sha256 = Digest::SHA2.new(256)
      aes = OpenSSL::Cipher.new("AES-256-CFB")

      key, iv = decode_encrypt_key(secret)
      key = sha256.digest(key)
      
      aes.decrypt
      aes.key = key
      aes.iv = iv
      
      encrypted_data = Base64.decode64(encoded_encrypted_data)
      payload = aes.update(encrypted_data) + aes.final
      
      return payload
    end

    extend self
    
  end
end