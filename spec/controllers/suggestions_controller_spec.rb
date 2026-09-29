require "rails_helper"

RSpec.describe SuggestionsController, type: :controller do
  login_admin_as_current_user
  let(:provider) { @current_user.current_provider }

  before do
    ActionMailer::Base.deliveries.clear
    allow(Suggestion).to receive(:enabled?).and_return(true)
  end

  it "is hidden while suggestions are switched off" do
    allow(Suggestion).to receive(:enabled?).and_return(false)
    expect { get :new }.to raise_error(ActionController::RoutingError)
    expect { post :create, params: { suggestion: { kind: "idea", body: "Idea" } } }.to raise_error(ActionController::RoutingError)
    expect(Suggestion.count).to eq 0
  end

  it "saves the suggestion with who sent it and the screen, and emails GCRPC I.T." do
    q = HelpQuestion.create!(user: @current_user, question: "How do I merge customers?")
    post :create, params: { suggestion: { kind: "question", body: "Need a merge button.", page_path: "/en/customers/12", help_question_id: q.id } }
    s = Suggestion.last
    expect(response).to redirect_to(suggestions_path)
    expect([s.user, s.provider, s.kind, s.screen, s.help_question, s.status]).to eq [@current_user, provider, "question", "Customers", q, "new"]
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq SuggestionMailer::RECIPIENTS
    expect(mail.subject).to include("A question from")
    expect(mail.body.encoded).to include("Need a merge button.", "Screen: Customers", "How do I merge customers?")
  end

  it "keeps the suggestion if the email fails" do
    allow(SuggestionMailer).to receive(:new_suggestion).and_raise(Errno::ECONNREFUSED)
    expect { post :create, params: { suggestion: { kind: "idea", body: "Idea" } } }.to change(Suggestion, :count).by(1)
    expect(response).to redirect_to(suggestions_path)
  end

  it "won't attach someone else's Ask RidePilot question" do
    theirs = HelpQuestion.create!(user: create(:user), question: "Private")
    post :create, params: { suggestion: { kind: "idea", body: "Idea", help_question_id: theirs.id } }
    expect(Suggestion.last.help_question_id).to be_nil
  end

  it "asks again when the text is empty" do
    post :create, params: { suggestion: { kind: "idea", body: "" } }
    expect(response.status).to eq 422
    expect(Suggestion.count).to eq 0
  end

  it "lets an admin mark status and reply; the sender sees only their own" do
    sender = create(:user, current_provider: provider)
    mine = Suggestion.create!(user: sender, provider: provider, body: "Bigger font")
    other = Suggestion.create!(user: create(:user), provider: provider, body: "Other")
    patch :update, params: { id: mine.id, suggestion: { status: "planned", reply: "Good idea, next week." } }
    expect(mine.reload.attributes.values_at("status", "reply", "replied_by_id")).to eq ["planned", "Good idea, next week.", @current_user.id]

    allow(sender).to receive(:admin?).and_return(false)
    allow(sender).to receive(:super_admin?).and_return(false)
    allow(controller).to receive(:current_user).and_return(sender)
    get :index
    expect(assigns(:suggestions)).to eq [mine]
    patch :update, params: { id: other.id, suggestion: { status: "done" } }
    expect(response.status).to eq 403
    expect(other.reload.status).to eq "new"
  end
end
