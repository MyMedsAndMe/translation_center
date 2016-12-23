# frozen_string_literal: true
require 'active_support'
require 'active_support/core_ext'
require 'translation_center/translations_transfer'
require 'i18n'

module TranslationCenter
  class FakeBackend
    def translations
      {
        en: {
          foo: 'bar',
          customer: { name: 'name' }
        },
        de: {
          foo: 'baren',
          customer: { name: 'benennung' }
        }
      }
    end

    def init_translations; end
  end

  class User; end

  RSpec.describe TranslationCenter do
    before :all do
      I18n.available_locales = [:en, :de]
    end

    let(:translator) { User.new }

    describe '.yaml2db' do
      before :each do
        expect(TranslationCenter).to receive(:prepare_translator).and_return(translator)
        expect(::I18n).to receive(:backend).at_least(:once) { FakeBackend.new }
      end

      it 'fetches :customer key' do
        expect(TranslationCenter)
          .to receive(:collect_keys)
          .exactly(:twice)
          .with([], hash_including(name: instance_of(String)))
          .and_return([])
        TranslationCenter.yaml2db
      end

      it 'store given locale only' do
        expect(TranslationCenter)
          .to receive(:yaml2db_keys).once
          .with(['name'], translator, [:en], en: { name: 'name' }, de: { name: 'benennung' })
        TranslationCenter.yaml2db(:en)
      end

      it 'store given all locales if none given' do
        expect(TranslationCenter)
          .to receive(:yaml2db_keys).once
          .with(['name'], translator, [:en, :de], en: { name: 'name' }, de: { name: 'benennung' })
        TranslationCenter.yaml2db
      end
    end
  end
end
