require "test_helper"

class UnifiedLogger::SeverityTest < UnifiedLoggerTestCase
  # -- Logger::Severity constants --

  test "NOTE constant is defined on Logger::Severity" do
    assert_equal 1.5, Logger::Severity::NOTE
  end

  test "NOTE is accessible via Logger::NOTE" do
    assert_equal 1.5, Logger::NOTE
  end

  test "NOTE is between INFO and WARN" do
    assert Logger::Severity::NOTE > Logger::Severity::INFO
    assert Logger::Severity::NOTE < Logger::Severity::WARN
  end

  # -- coerce with :note (Ruby 3.3+ / logger gem >= 1.6) --

  if Logger::Severity.respond_to?(:coerce)
    test "coerce accepts :note symbol" do
      assert_equal 1.5, Logger::Severity.coerce(:note)
    end

    test "coerce accepts 'note' string" do
      assert_equal 1.5, Logger::Severity.coerce("note")
    end

    test "coerce accepts 'NOTE' string" do
      assert_equal 1.5, Logger::Severity.coerce("NOTE")
    end

    test "coerce accepts numeric 1.5" do
      assert_equal 1.5, Logger::Severity.coerce(1.5)
    end

    test "coerce still works for standard levels" do
      assert_equal 0, Logger::Severity.coerce(:debug)
      assert_equal 1, Logger::Severity.coerce(:info)
      assert_equal 2, Logger::Severity.coerce(:warn)
      assert_equal 3, Logger::Severity.coerce(:error)
      assert_equal 4, Logger::Severity.coerce(:fatal)
      assert_equal 5, Logger::Severity.coerce(:unknown)
    end
  end

  # -- plain ::Logger accepts :note --

  test "plain Ruby Logger accepts :note as level" do
    logger = ::Logger.new(StringIO.new)
    logger.level = :note
    assert_equal 1.5, logger.level
  end

  test "plain Ruby Logger accepts 'note' string as level" do
    logger = ::Logger.new(StringIO.new)
    logger.level = "note"
    assert_equal 1.5, logger.level
  end
end
