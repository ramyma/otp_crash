defmodule OtpCrashWeb.ErrorJSONTest do
  use OtpCrashWeb.ConnCase, async: true

  test "renders 404" do
    assert OtpCrashWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert OtpCrashWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
