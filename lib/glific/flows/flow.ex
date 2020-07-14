defmodule Glific.Flows.Flow do
  @moduledoc """
  The flow object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """
  alias __MODULE__

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Flows.FlowContext,
    Flows.FlowRevision,
    Flows.Node,
    Repo,
    Settings.Language
  }

  @required_fields [:name, :language_id, :uuid]
  @optional_fields [:flow_type, :version_number, :shortcode, :uuid_map, :nodes]

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          name: String.t() | nil,
          shortcode: String.t() | nil,
          uuid: Ecto.UUID.t() | nil,
          uuid_map: map() | nil,
          flow_type: String.t() | nil,
          nodes: [Node.t()] | nil,
          version_number: String.t() | nil,
          language_id: non_neg_integer | nil,
          language: Language.t() | Ecto.Association.NotLoaded.t() | nil,
          revisions: [FlowRevision.t()] | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "flows" do
    field :name, :string
    field :shortcode, :string

    field :version_number, :string
    field :flow_type, :string
    field :uuid, Ecto.UUID

    field :uuid_map, :map, virtual: true
    field :nodes, :map, virtual: true

    belongs_to :language, Language

    has_many :revisions, FlowRevision

    timestamps(type: :utc_datetime)
  end

  @doc """
  Return the list of filtered tags
  """
  @spec list_flows(map()) :: [Flow.t()]
  def list_flows(args \\ %{}),
    do: Repo.list_filter(args, Flow, &Repo.opts_with_name/2, &Repo.filter_with/2)

  @doc """
  Get a single flow
  """
  @spec get_flow!(integer) :: Flow.t()
  def get_flow!(id), do: Repo.get!(Flow, id)

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(Flow.t(), map()) :: Ecto.Changeset.t()
  def changeset(flow, attrs) do
    flow
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:language_id)
  end

  @doc """
  Process a json structure from floweditor to the Glific data types
  """
  @spec process(map(), Flow.t()) :: Flow.t()
  def process(json, flow) do
    {nodes, uuid_map} =
      Enum.reduce(
        json["nodes"],
        {[], %{}},
        fn node_json, acc ->
          {node, uuid_map} = Node.process(node_json, elem(acc, 1), flow)
          {[node | elem(acc, 0)], uuid_map}
        end
      )

    flow
    |> Map.put(:uuid_map, uuid_map)
    |> Map.put(:nodes, Enum.reverse(nodes))
  end

  @doc """
  Build the context so we can execute the flow
  """
  @spec context(Flow.t(), Contact.t()) :: {:ok, FlowContext.t()} | {:error, String.t()}
  def context(%Flow{nodes: nodes}, _contact) when nodes == [],
    do: {:error, "An empty flow cannot have a context or be executed"}

  def context(flow, contact) do
    # get the first node
    node = hd(flow.nodes)

    attrs = %{
      contact: contact,
      contact_id: contact.id,
      flow_id: flow.id,
      uuid_map: flow.uuid_map,
      node_uuid: node.uuid
    }

    {:ok, context} =
      %FlowContext{}
      |> FlowContext.changeset(attrs)
      |> Repo.insert()

    context
    |> Repo.preload(:contact)
    |> Map.put(:node, node)
  end

  # in some cases floweditor wraps the json under a "definition" key
  @spec clean_definition(map()) :: map()
  defp clean_definition(json),
    do: elem(Map.pop(json, "definition", json), 0) |> Map.delete("_ui")

  @doc """
  load the latest revision, specifically json definition from the
  flow_revision table. We return the clean definition back
  """
  @spec get_latest_definition(integer) :: map()
  def get_latest_definition(flow_id) do
    query =
      from fr in FlowRevision,
        where: fr.revision_number == 0 and fr.flow_id == ^flow_id,
        select: fr.definition

    Repo.one(query)
    # lets get rid of stuff we don't use, specfically the definition and
    # UI layout of the flow
    |> clean_definition()
  end

  @doc """
  Load the latest revision for a specific flow and setup for
  flow execution.

  The args can be a specific filter. For now, the calling function
  either sends a shortcode map or a flow_uuid map
  """
  @spec load_flow(map()) :: Flow.t() | nil
  def load_flow(args) do
    case Repo.fetch_by(Flow, args) do
      {:ok, flow} ->
        flow.id
        |> get_latest_definition()
        |> process(flow)

      _ ->
        nil
    end
  end

  @doc """
  Start a flow, given a shortcode and a contact_id
  """
  @spec start_flow(String.t(), Contact.t()) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def start_flow(shortcode, contact) do
    flow = load_flow(%{shortcode: shortcode})

    FlowContext.init_context(flow, contact)
  end

  @doc """
  Create a subflow of an existing flow
  """
  @spec start_sub_flow(FlowContext.t(), Ecto.UUID.t()) ::
          {:ok, FlowContext.t(), [String.t()]} | {:error, String.t()}
  def start_sub_flow(context, uuid) do
    # we might want to put the current one under some sort of pause status
    flow = load_flow(%{uuid: uuid})

    FlowContext.init_context(flow, context.contact, context.id)
  end
end
