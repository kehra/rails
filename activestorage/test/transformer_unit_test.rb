# frozen_string_literal: true

require "test_helper"
require "active_storage/transformers/image_magick"
require "active_storage/transformers/null_transformer"
require "active_storage/transformers/vips"

class ActiveStorage::TransformerUnitTest < ActiveSupport::TestCase
  test "base transformer stores transformations and requires process implementation" do
    transformations = { resize_to_limit: [100, 100] }
    transformer = ActiveStorage::Transformers::Transformer.new(transformations)

    assert_same transformations, transformer.transformations
    assert_raises(NotImplementedError) do
      transformer.transform(file_fixture("racecar.jpg").open, format: :png) { }
    end
  end

  test "transform yields processed file and closes it afterward" do
    file = Tempfile.new("active-storage-transformer-test")
    path = file.path
    transformer = ActiveStorage::Transformers::NullTransformer.new({})
    yielded = nil

    result = transformer.transform(file, format: :png) do |output|
      yielded = output
      :transformed
    end

    assert_equal :transformed, result
    assert_same file, yielded
    assert_predicate file, :closed?
    assert_not File.exist?(path)
  end

  test "image processing transformer rejects combine options" do
    transformer = ActiveStorage::Transformers::ImageProcessingTransformer.new(combine_options: { resize: "100x100" })

    assert_raises(ArgumentError) do
      transformer.send(:operations)
    end
  end

  test "image magick validates nested safe operation arguments" do
    transformer = ActiveStorage::Transformers::ImageMagick.new(
      resize_to_limit: [100, 100, nil, { width: 100, height: "200", nested: { flag: nil } }],
      auto_orient: true,
      rotate: nil
    )

    assert_equal [ [ :resize_to_limit, [100, 100, nil, { width: 100, height: "200", nested: { flag: nil } }] ], [ :auto_orient, true ] ], transformer.send(:operations)
  end

  test "vips exposes image processing vips processor" do
    assert_equal ImageProcessing::Vips, ActiveStorage::Transformers::Vips.new({}).processor
  end
end
