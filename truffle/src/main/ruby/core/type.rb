# Copyright (c) 2007-2015, Evan Phoenix and contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of Rubinius nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# Copyright (c) 2011, Evan Phoenix
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name of the Evan Phoenix nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# The Type module provides facilities for accessing various "type" related
# data about an object, as well as providing type coercion methods. These
# facilities are independent of the object and thus are more robust in the
# face of ad hoc monkeypatching.

##
# Namespace for coercion functions between various ruby objects.

module Rubinius
  module Type

    # Performs a direct kind_of? check on the object bypassing any method
    # overrides.
    def self.object_kind_of?(obj, cls)
      Truffle.primitive :vm_object_kind_of
      raise PrimitiveFailure, "Rubinius::Type.object_kind_of? primitive failed"
    end

    def self.object_class(obj)
      Truffle.primitive :vm_object_class
      raise PrimitiveFailure, "Rubinius::Type.object_class primitive failed"
    end

    def self.singleton_class_object(mod)
      Truffle.primitive :vm_singleton_class_object
      raise PrimitiveFailure, "Rubinius::Type.singleton_class_object primitive failed"
    end

    def self.object_respond_to?(obj, name, include_private = false)
      Truffle.invoke_primitive :vm_object_respond_to, obj, name, include_private
    end

    def self.object_equal(a, b)
      Truffle.primitive :vm_object_equal
      raise PrimitiveFailure, "Rubinius::Type.object_equal primitive failed"
    end

    def self.module_name(mod)
      Truffle.primitive :vm_get_module_name
      raise PrimitiveFailure, "Rubinius::Type.module_name primitive failed"
    end

    def self.module_inspect(mod)
      sc = singleton_class_object mod

      if sc
        case sc
          when Class, Module
            name = "#<Class:#{module_inspect(sc)}>"
          else
            cls = object_class sc
            name = "#<Class:#<#{module_name(cls)}:0x#{sc.object_id.to_s(16)}>>"
        end
      else
        name = module_name mod
        if !name or name == ""
          name = "#<#{object_class(mod)}:0x#{mod.object_id.to_s(16)}>"
        end
      end

      name
    end

    def self.coerce_string_to_float(string, strict)
      value = Truffle.invoke_primitive :string_to_f, string, strict
      raise ArgumentError, "invalid string for Float" if value.nil?
      value
    end

    def self.coerce_object_to_float(obj)
      case obj
        when Float
          obj
        when nil
          raise TypeError, "can't convert nil into Float"
        when Complex
          if obj.respond_to?(:imag) && obj.imag.equal?(0)
            coerce_to obj, Float, :to_f
          else
            raise RangeError, "can't convert #{obj} into Float"
          end
        else
          coerce_to obj, Float, :to_f
      end
    end

    def self.object_encoding(obj)
      Truffle.primitive :encoding_get_object_encoding
      raise PrimitiveFailure, "Rubinius::Type.object_encoding primitive failed"
    end

    ##
    # Returns an object of given class. If given object already is one, it is
    # returned. Otherwise tries obj.meth and returns the result if it is of the
    # right kind. TypeErrors are raised if the conversion method fails or the
    # conversion result is wrong.
    #
    # Uses Rubinius::Type.object_kind_of to bypass type check overrides.
    #
    # Equivalent to MRI's rb_convert_type().

    def self.coerce_to(obj, cls, meth)
      return obj if object_kind_of?(obj, cls)
      execute_coerce_to(obj, cls, meth)
    end

    def self.execute_coerce_to(obj, cls, meth)
      begin
        ret = obj.__send__(meth)
      rescue Exception => orig
        coerce_to_failed obj, cls, meth, orig
      end

      return ret if object_kind_of?(ret, cls)

      coerce_to_type_error obj, ret, meth, cls
    end

    def self.coerce_to_failed(object, klass, method, exc=nil)
      if object_respond_to? object, :inspect
        raise TypeError,
            "Coercion error: #{object.inspect}.#{method} => #{klass} failed",
            exc
      else
        raise TypeError,
            "Coercion error: #{method} => #{klass} failed",
            exc
      end
    end

    def self.coerce_to_type_error(original, converted, method, klass)
      oc = object_class original
      cc = object_class converted
      msg = "failed to convert #{oc} to #{klass}: #{oc}\##{method} returned #{cc}"
      raise TypeError, msg
    end

    ##
    # Same as coerce_to but returns nil if conversion fails.
    # Corresponds to MRI's rb_check_convert_type()
    #
    def self.check_convert_type(obj, cls, meth)
      return obj if object_kind_of?(obj, cls)
      return nil unless object_respond_to?(obj, meth, true)
      execute_check_convert_type(obj, cls, meth)
    end

    def self.execute_check_convert_type(obj, cls, meth)
      begin
        ret = obj.__send__(meth)
      rescue Exception
        return nil
      end

      return ret if ret.nil? || object_kind_of?(ret, cls)

      msg = "Coercion error: obj.#{meth} did NOT return a #{cls} (was #{object_class(ret)})"
      raise TypeError, msg
    end

    ##
    # Uses the logic of [Array, Hash, String].try_convert.
    #
    def self.try_convert(obj, cls, meth)
      return obj if object_kind_of?(obj, cls)
      return nil unless obj.respond_to?(meth)
      execute_try_convert(obj, cls, meth)
    end

    def self.execute_try_convert(obj, cls, meth)
      ret = obj.__send__(meth)

      return ret if ret.nil? || object_kind_of?(ret, cls)

      msg = "Coercion error: obj.#{meth} did NOT return a #{cls} (was #{object_class(ret)})"
      raise TypeError, msg
    end

    def self.coerce_to_comparison(a, b)
      unless cmp = (a <=> b)
        raise ArgumentError, "comparison of #{a.inspect} with #{b.inspect} failed"
      end
      cmp
    end

    def self.coerce_to_collection_index(index)
      return index if object_kind_of? index, Fixnum

      method = :to_int
      klass = Fixnum

      begin
        idx = index.__send__ method
      rescue Exception => exc
        coerce_to_failed index, klass, method, exc
      end
      return idx if object_kind_of? idx, klass

      if object_kind_of? index, Bignum
        raise RangeError, "Array index must be a Fixnum (passed Bignum)"
      else
        coerce_to_type_error index, idx, method, klass
      end
    end

    def self.coerce_to_collection_length(length)
      return length if object_kind_of? length, Fixnum

      method = :to_int
      klass = Fixnum

      begin
        size = length.__send__ method
      rescue Exception => exc
        coerce_to_failed length, klass, method, exc
      end
      return size if object_kind_of? size, klass

      if object_kind_of? size, Bignum
        raise ArgumentError, "Array size must be a Fixnum (passed Bignum)"
      else
        coerce_to_type_error length, size, :to_int, Fixnum
      end
    end

    def self.coerce_to_regexp(pattern, quote=false)
      case pattern
      when Regexp
        return pattern
      when String
        # nothing
      else
        pattern = StringValue(pattern)
      end

      pattern = Regexp.quote(pattern) if quote
      Regexp.new(pattern)
    end

    # Taint host if source is tainted.
    def self.infect(host, source)
      Truffle.primitive :object_infect
      raise PrimitiveFailure, "Object.infect primitive failed"
    end

    def self.coerce_to_encoding(obj)
      case obj
      when Encoding
        return obj
      when String
        return Encoding.find obj
      else
        return Encoding.find StringValue(obj)
      end
    end

    def self.try_convert_to_encoding(obj)
      case obj
      when Encoding
        return obj
      when String
        str = obj
      else
        str = StringValue obj
      end

      key = str.upcase.to_sym

      pair = Encoding::EncodingMap[key]
      if pair
        index = pair.last
        return index && Encoding::EncodingList[index]
      end

      return undefined
    end

    def self.coerce_to_path(obj)
      if object_kind_of?(obj, String)
        obj
      else
        if object_respond_to? obj, :to_path
          obj = obj.to_path
        end

        StringValue(obj)
      end
    end

    def self.coerce_to_symbol(obj)
      return obj if object_kind_of? obj, Symbol

      obj = obj.to_str if obj.respond_to?(:to_str)
      coerce_to(obj, Symbol, :to_sym)
    end

    # Equivalent of num_exact in MRI's time.c; used by Time methods.
    def self.coerce_to_exact_num(obj)
      if obj.kind_of?(Integer)
        obj
      elsif obj.kind_of?(String)
        raise TypeError, "can't convert #{obj} into an exact number"
      elsif obj.nil?
        raise TypeError, "can't convert nil into an exact number"
      else
        check_convert_type(obj, Rational, :to_r) || coerce_to(obj, Integer, :to_int)
      end
    end

    def self.coerce_to_utc_offset(offset)
      offset = String.try_convert(offset) || offset

      if offset.kind_of?(String)
        unless offset.encoding.ascii_compatible? && offset.match(/\A(\+|-)(\d\d):(\d\d)\z/)
          raise ArgumentError, '"+HH:MM" or "-HH:MM" expected for utc_offset'
        end

        offset = $2.to_i*60*60 + $3.to_i*60
        offset = -offset if $1.ord == 45
      else
        offset = Rubinius::Type.coerce_to_exact_num(offset)
      end

      if offset <= -86400 || offset >= 86400
        raise ArgumentError, "utc_offset out of range"
      end

      offset
    end

    def self.coerce_to_bitwise_operand(obj)
      if object_kind_of? obj, Float
        raise TypeError, "can't convert Float into Integer for bitwise arithmetic"
      end
      coerce_to obj, Integer, :to_int
    end

    def self.binary_string(string)
      string.force_encoding Encoding::BINARY
    end

    def self.external_string(string)
      string.force_encoding Encoding.default_external
    end

    def self.encode_string(string, enc)
      string.force_encoding enc
    end

    def self.ascii_compatible_encoding(string)
      compatible_encoding string, Encoding::US_ASCII
    end

    def self.compatible_encoding(a, b)
      enc = Encoding.compatible? a, b

      unless enc
        enc_a = object_encoding a
        enc_b = object_encoding b
        message = "undefined conversion "
        message << "for '#{a.inspect}' " if object_kind_of?(a, String)
        message << "from #{enc_a} to #{enc_b}"

        raise Encoding::CompatibilityError, message
      end

      enc
    end

    def self.object_respond_to__dump?(obj)
      object_respond_to? obj, :_dump, true
    end

    def self.object_respond_to_marshal_dump?(obj)
      object_respond_to? obj, :marshal_dump, true
    end

    def self.object_respond_to_marshal_load?(obj)
      object_respond_to? obj, :marshal_load, true
    end
  end
end
