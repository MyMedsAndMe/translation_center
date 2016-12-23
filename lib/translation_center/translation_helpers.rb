module TranslationCenter
  CUSTOMER_KEY_ROOT = 'customer.'.freeze
  KEYS_SEPARATOR = '.'.freeze
  ALL_PLURALS = { one: 'one', two: 'two', few: 'few', many: 'many', other: 'other' }

  # Return the default translator by building and returning the translator object
  def self.prepare_translator
    translator = TranslationCenter::CONFIG['translator_type'].camelize.constantize.where(TranslationCenter::CONFIG['identifier_type'] => TranslationCenter::CONFIG['yaml_translator_identifier']).first

    # if translator doesn't exist then create him
    if translator.blank?
      translator = TranslationCenter::CONFIG['translator_type'].camelize.constantize.new
      translator.send "#{TranslationCenter::CONFIG['identifier_type']}=", TranslationCenter::CONFIG['yaml_translator_identifier']
      begin
        translator.save(validate: false)
        # needed if the user is using confirmable with devise
        translator.update_attribute(:confirmed_at, Time.now) if translator.attributes.has_key?('confirmed_at')
      rescue
        translator = nil
      end
    end
    translator
  end

  def self.included(base)
    base.class_eval do
      alias_method_chain(:translate, :adding) if TranslationCenter::CONFIG['enabled']
    end
  end

  # wraps a span if inspector option is set to all
  def wrap_span(translation, translation_key)
    # put the inspector class if inspector is all and the key doesn't belongs to translation_center
    if TranslationCenter::CONFIG['inspector'] == 'all' && translation_key.name.to_s.split(KEYS_SEPARATOR).first != 'translation_center'
      "<span class='tc-inspector-key' data-locale='#{I18n.locale}' data-type='#{translation_key.status(I18n.locale)}' data-id='#{translation_key.id}'> #{translation} </span>".html_safe
    else
      translation
    end
  end

  # make sure the complete key is build using the options such as scope and count
  def prepare_key(locale, key, options)
    return key if key.blank?

    scope = Array(options.fetch(:scope, '')).join(KEYS_SEPARATOR).to_s
    complete_key = [scope.presence, key].compact.join(KEYS_SEPARATOR)

    # add the correct count suffix
    if count = options.fetch(:count, nil).presence
      plural_form = I18n.backend.send :pluralize, locale, ALL_PLURALS, count
      complete_key = "#{complete_key}.#{plural_form}"
    end

    complete_key
  end

  def non_customer_key?(key)
    !key.start_with?(CUSTOMER_KEY_ROOT)
  end

  def translate_with_adding(locale, key, options = {})
    complete_key = prepare_key(locale, key, options)

    return translate_without_adding(locale, key, options) if complete_key.blank? || non_customer_key?(complete_key)

    stripped_key = complete_key.sub(CUSTOMER_KEY_ROOT, '')
    translation_key = TranslationCenter::TranslationKey.find_or_create_by(name: stripped_key)
    translation_key.update_column(:last_accessed, Time.now)

    # save the default value (Which is the titleized key name as the translation) if the option is enabled and no translation exists for that key in the db
    translation_key.create_default_translation if TranslationCenter::CONFIG['save_default_translation'] && translation_key.translations.in(:en).empty? && !translation_key.has_children?

    # if i18n_source is set to db and not overriden by options then fetch from db
    if TranslationCenter::CONFIG['i18n_source']  == 'db' && options.delete(:yaml).blank?
      val = translation_key.accepted_translation_in(locale).try(:value) || options[:default]
      # replace variables in a translation with passed values
      options.each_pair{ |key, value| val.gsub!("%{#{key.to_s}}", value.to_s) } if val.is_a?(String)

      if val.blank? && !translation_key.has_children?
        throw(:exception, I18n::MissingTranslation.new(locale, complete_key, options))
      elsif translation_key.has_children?
        # TODO should use ancestors for keys
        return translation_key.children_translations(locale)
      end
      wrap_span(val, translation_key)
    else
      translation_value = translate_without_adding(locale, key, options)
      translation_value.class == Hash ? translation_value : wrap_span(translation_value, translation_key)
    end
  end

  # load tha translation config
  if FileTest.exists?("config/translation_center.yml")
    TranslationCenter::CONFIG = YAML.load_file("config/translation_center.yml")[Rails.env]
    # identifier is by default email
    TranslationCenter::CONFIG['identifier_type'] ||= 'email'
    TranslationCenter::CONFIG['translator_type'] ||= 'User'
  else
    puts "WARNING: translation_center will be using default options if config/translation_center.yml doesn't exists"
    TranslationCenter::CONFIG = {'enabled' => false, 'inspector' => 'missing', 'lang' => {'en' => {'name' => 'English', 'direction' => 'ltr'}}, 'yaml_translator_identifier' => 'coder@tc.com', 'i18n_source' => 'yaml', 'yaml2db_translations_accepted' => true,
                                'accept_admin_translations' => true,  'save_default_translation' => true, 'identifier_type' => 'email', 'translator_type' => 'User' }
  end

  I18n.available_locales = TranslationCenter::CONFIG['lang'].keys
end

# override html_message to add a class to the returned span
module I18n
  class MissingTranslation
    module Base
      # added another class to be used
      def html_message
        category = keys.first
        key = keys.last.to_s.tr('_', ' ').gsub(/\b('?[a-z])/) { |match| match.capitalize }
        translation_key = keys
        # remove locale
        translation_key.shift

        translation_key = TranslationCenter::TranslationKey.find_by_name(translation_key.join(KEYS_SEPARATOR))
        # don't put the inspector class if inspector is off or the key belongs to translation_center
        if TranslationCenter::CONFIG['inspector'] == 'off' || category == 'translation_center'
          %(<span class="translation_missing" title="translation missing: #{keys.join(KEYS_SEPARATOR)}">#{key}</span>)
        else
          %(<span class="translation_missing tc-inspector-key" data-locale='#{I18n.locale}' data-type="#{translation_key.status(I18n.locale)}" data-id="#{translation_key.id}" title="translation missing: #{keys.join(KEYS_SEPARATOR)}">#{key}</span>)
        end
      end
    end
  end
end

I18n::Backend::Base.send :include, TranslationCenter
