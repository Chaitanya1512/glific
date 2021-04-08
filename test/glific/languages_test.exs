defmodule Glific.LanguagesTest do
  use Glific.DataCase
  use ExUnit.Case

  alias Glific.{
    Fixtures,
    Settings
  }

  describe "languages" do
    test "list_languages/1 with language filtered",
         %{organization_id: _organization_id} = attrs do
      _language1 = Fixtures.language_fixture(attrs)
      language2 = Fixtures.language_fixture(Map.merge(%{localized: true}, attrs))

      languages =
        Settings.list_languages(%{
          filter: %{localized: true}
        })

      assert length(languages) == 3
      assert language2 in languages
    end
  end
end
