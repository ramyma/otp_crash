defmodule OtpCrashWeb.Router do
  use OtpCrashWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", OtpCrashWeb do
    pipe_through :api
  end
end
