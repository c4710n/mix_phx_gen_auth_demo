defmodule Demo.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, Demo.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %Demo.Accounts.UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token.
  """
  def verify_session_token_query(token) do
    query =
      from token in token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(60, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds a token with a hashed counter part.

  The non-hashed token is sent to the user e-mail while the
  hashed part is stored in the database, to avoid reconstruction.
  The token is valid for a week as long as users don't change
  their email.
  """
  def build_user_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Demo.Accounts.UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token.
  """
  def verify_user_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(1, "week") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token.
  """
  def verify_user_change_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(1, "week")

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the given token with the given context.
  """
  def token_and_context_query(token, context) do
    from Demo.Accounts.UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def user_and_contexts_query(user, :all) do
    from t in Demo.Accounts.UserToken, where: t.user_id == ^user.id
  end

  def user_and_contexts_query(user, [_ | _] = contexts) do
    from t in Demo.Accounts.UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end
