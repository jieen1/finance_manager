module Account::Linkable
  extend ActiveSupport::Concern

  # All accounts are unlinked/manual since Plaid has been removed
  def linked?
    false
  end

  # An "offline" or "unlinked" account is one where the user tracks values and
  # adds transactions manually
  def unlinked?
    true
  end
  alias_method :manual?, :unlinked?
end
