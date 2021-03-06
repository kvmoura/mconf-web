# This file is part of Mconf-Web, a web application that provides access
# to the Mconf webconferencing system. Copyright (C) 2010-2015 Mconf.
#
# This file is licensed under the Affero General Public License version
# 3 or later. See the LICENSE file.

require 'spec_helper'

describe ManageController do

  let!(:referer) { "http://#{Site.current.domain}" }
  before { request.env["HTTP_REFERER"] = referer }

  describe "#users" do
    before { User.destroy_all } # exclude seeded user(s)

    it "should require authentication"

    # see bug #1719
    context "stores location for redirect from xhr" do
      let(:superuser) { FactoryGirl.create(:superuser) }
      let(:user) { FactoryGirl.create(:user) }
      before {
        sign_in superuser
        controller.session[:user_return_to] = "/home"
        request.env['CONTENT_TYPE'] = "text/html"
        xhr :get, :users
      }
      it { controller.session[:user_return_to].should eq("/manage/users") }
      it { controller.session[:previous_user_return_to].should eq("/home") }
    end

    context "authorizes" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { sign_in(user) }
      it { should_authorize :manage, :spaces }
    end

    describe "if the current user is a superuser" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { sign_in(user) }

      it {
        get :users
        should respond_with(:success)
      }

      context "sets @users to a list of all users, including disabled users" do
        before {
          @u1 = user
          @u2 = FactoryGirl.create(:user, :disabled => false)
          @u3 = FactoryGirl.create(:user, :disabled => true)
        }
        before(:each) { get :users }
        it { assigns(:users).count.should be(3) }
        it { assigns(:users).should include(@u1) }
        it { assigns(:users).should include(@u2) }
        it { assigns(:users).should include(@u3) }
      end

      it "eager loads user profiles" do
        FactoryGirl.create(:user)
        get :users
        assigns(:users).each do |user|
          user.association(:profile).loaded?.should be_truthy
        end
      end

      context "orders @users by the user's full name" do
        before {
          @u1 = FactoryGirl.create(:user, :_full_name => 'Last one')
          @u2 = user
          @u2.profile.update_attributes(:full_name => 'Ce user')
          @u3 = FactoryGirl.create(:user, :_full_name => 'A user')
          @u4 = FactoryGirl.create(:user, :_full_name => 'Be user')
        }
        before(:each) { get :users }
        it { assigns(:users).count.should be(4) }
        it { assigns(:users)[0].should eql(@u3) }
        it { assigns(:users)[1].should eql(@u4) }
        it { assigns(:users)[2].should eql(@u2) }
        it { assigns(:users)[3].should eql(@u1) }
      end

      context "paginates the list of users" do
        before {
          45.times { FactoryGirl.create(:user) }
        }

        context "if no page is passed in params" do
          before(:each) { get :users }
          it { assigns(:users).size.should be(20) }
          it { controller.params[:page].should be_nil }
        end

        context "if a page is passed in params" do
          before(:each) { get :users, :page => 2 }
          it { assigns(:users).size.should be(20) }
          it("includes the correct users in @users") {
            page = User.joins(:profile).order("profiles.full_name").paginate(:page => 2, :per_page => 20)
            page.each do |user|
              assigns(:users).should include(user)
            end
          }
          it { controller.params[:page].should eql("2") }
        end
      end

      context "use params[:q] to filter the results" do

        context "by full name" do
          before {
            @u1 = User.first
            @u1.profile.update_attributes(:full_name => 'First')
            @u2 = user
            @u2.profile.update_attributes(:full_name => 'Second')
            @u3 = FactoryGirl.create(:user, :_full_name => 'Secondary')
          }
          before(:each) { get :users, :q => 'second' }
          it { assigns(:users).count.should be(2) }
          it { assigns(:users).should include(@u2) }
          it { assigns(:users).should include(@u3) }
        end

        context "by username" do
          before {
            @u1 = FactoryGirl.create(:user, :username => 'First')
            @u2 = user
            @u2.update_attributes(:username => 'Second')
            @u3 = FactoryGirl.create(:user, :username => 'Secondary')
          }
          before(:each) { get :users, :q => 'second' }
          it { assigns(:users).count.should be(2) }
          it { assigns(:users).should include(@u2) }
          it { assigns(:users).should include(@u3) }
        end

        context "by email" do
          before {
            @u1 = FactoryGirl.create(:user, :email => 'first@here.com')
            @u2 = FactoryGirl.create(:user, :email => 'second@there.com')
            @u3 = FactoryGirl.create(:user, :email => 'my@secondary.org')
          }
          before(:each) { get :users, :q => 'second' }
          it { assigns(:users).count.should be(2) }
          it { assigns(:users).should include(@u2) }
          it { assigns(:users).should include(@u3) }
        end

      end

      context "use params [:admin, :approved, :disabled, :can_record] to filter the results" do
        let!(:users) {[
          FactoryGirl.create(:user, username: 'el-magron'),
          FactoryGirl.create(:superuser, username: 'el-admin'),
          FactoryGirl.create(:user, username: 'el-debilitado', disabled: true),
          FactoryGirl.create(:user, username: 'reprovado'),
          FactoryGirl.create(:user, username: 'remembrador', can_record: true),
          User.first # the original admin user
        ]}
        before {
          users[3].disapprove!
          get :users, params
        }

        context "no params" do
          let(:params) { {} }

          it { assigns(:users).count.should be(6) }
          it { assigns(:users).should include(*users) }
        end

        context "params[:admin]" do
          context 'is true' do
            let(:params) { {admin: 'true'} }
            it { assigns(:users).count.should be(2) }
            it { assigns(:users).should include(users[1], users[5]) }
          end

          context 'is false' do
            let(:params) { {admin: 'false'} }
            it { assigns(:users).count.should be(4) }
            it { assigns(:users).should include(users[0], users[2], users[3], users[4]) }
          end
        end

        context "params[:approved]" do
          context 'is true' do
            let(:params) { {approved: 'true'} }
            it { assigns(:users).count.should be(5) }
            it { assigns(:users).should include(users[0], users[1], users[2], users[4], users[5]) }
          end

          context 'is false' do
            let(:params) { {approved: 'false'} }
            it { assigns(:users).count.should be(1) }
            it { assigns(:users).should include(users[3]) }
          end
        end

        context "params[:disabled]" do
          context 'is true' do
            let(:params) { {disabled: 'true'} }
            it { assigns(:users).count.should be(1) }
            it { assigns(:users).should include(users[2]) }
          end

          context 'is false' do
            let(:params) { {disabled: 'false'} }
            it { assigns(:users).count.should be(5) }
            it { assigns(:users).should include(users[0], users[1], users[3], users[4], users[5]) }
          end
        end

        context "params[:can_record]" do
          context 'is true' do
            let(:params) { {can_record: 'true'} }
            it { assigns(:users).count.should be(1) }
            it { assigns(:users).should include(users[4]) }
          end

          context 'is false' do
            let(:params) { {can_record: 'false'} }
            it { assigns(:users).count.should be(5) }
            it { assigns(:users).should include(users[0], users[1], users[2], users[3], users[5]) }
          end
        end

        context "mixed params" do
          let(:params) { {admin: 'false', approved: 'true', q: 'el re'} }

          it { assigns(:users).count.should be(3) }
          it { assigns(:users).should include(users[0], users[2], users[4]) }
        end
      end

      context "use params [:login_method_shib, :login_method_ldap, :login_method_local] to filter the results" do
        let!(:users) {[
          FactoryGirl.create(:user, username: 'el-magron'),
          FactoryGirl.create(:ldap_token, identifier: 'el-ldap', new_account: true).user,
          FactoryGirl.create(:shib_token, identifier: 'el-shib', new_account: true).user,
          FactoryGirl.create(:ldap_token, identifier: 'el-ldap-e-local', new_account: false).user,
          FactoryGirl.create(:shib_token, identifier: 'el-shib-e-local', new_account: false).user,
          FactoryGirl.create(:shib_token, identifier: 'el-shib-e-ldap-e-local', new_account: false).user,
          User.first # the original admin user
        ]}
        before {
          FactoryGirl.create(:ldap_token, user: users[5])
          get :users, params
        }

        context "no params" do
          let(:params) { {} }

          it { assigns(:users).count.should be(7) }
          it("includes all users") { assigns(:users).should include(*users) }
        end

        context "params[:login_method_shib]" do
          let(:params) { {login_method_shib: 'true'} }
          it { assigns(:users).count.should be(3) }
          it("includes all shibs") { assigns(:users).should include(users[2], users[4], users[5]) }
        end

        context "params[:login_method_ldap]" do
          let(:params) { {login_method_ldap: 'true'} }
          it { assigns(:users).count.should be(3) }
          it("includes all ldaps") { assigns(:users).should include(users[1], users[3], users[5]) }
        end

        context "params[:login_method_local]" do
          let(:params) { {login_method_local: 'true'} }
          it { assigns(:users).count.should be(5) }
          it("includes all locals") { assigns(:users).should include(users[0], users[3], users[4], users[5], users[6]) }
        end

        context "params[:login_method_local] and params[:login_method_shib]" do
          let(:params) { {login_method_local: 'true', login_method_shib: 'true'} }
          it { assigns(:users).count.should be(2) }
          it("includes all locals and shibs") { assigns(:users).should include(users[4], users[5]) }
        end

        context "params[:login_method_ldap] and params[:login_method_shib]" do
          let(:params) { {login_method_ldap: 'true', login_method_shib: 'true'} }
          it { assigns(:users).count.should be(1) }
          it("includes all ldaps and shibs") { assigns(:users).should include(users[5]) }
        end

        context "params[:login_method_ldap] and params[:login_method_shib] and params[:login_method_local]" do
          let(:params) { {login_method_ldap: 'true', login_method_shib: 'true', login_method_local: 'true'} }
          it { assigns(:users).count.should be(1) }
          it("includes all ldaps and shibs and locals") { assigns(:users).should include(users[5]) }
        end

      end

      context "if xhr request" do
        before(:each) { xhr :get, :users }
        it { should render_template('manage/_users_list') }
        it { should_not render_with_layout }
      end

      context "not xhr request" do
        before(:each) { get :users }
        it { should render_template(:users) }
        it { should render_with_layout('no_sidebar') }
      end
    end
  end

  describe "#spaces" do
    it "should require authentication"

    context "authorizes" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { sign_in(user) }
      it { should_authorize :manage, :spaces }
    end

    describe "if the current user is a superuser" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { sign_in(user) }

      it {
        get :spaces
        should respond_with(:success)
      }

      context "sets @spaces to a list of all spaces, including disabled spaces" do
        before {
          @s1 = FactoryGirl.create(:space, :disabled => false)
          @s2 = FactoryGirl.create(:space, :disabled => false)
          @s3 = FactoryGirl.create(:space, :disabled => true)
        }
        before(:each) { get :spaces }
        it { assigns(:spaces).count.should be(3) }
        it { assigns(:spaces).should include(@s1) }
        it { assigns(:spaces).should include(@s2) }
        it { assigns(:spaces).should include(@s3) }
      end

      context "orders @spaces by name" do
        before {
          @s1 = FactoryGirl.create(:space, :name => 'Last one')
          @s2 = FactoryGirl.create(:space, :name => 'Ce space')
          @s3 = FactoryGirl.create(:space, :name => 'A space')
          @s4 = FactoryGirl.create(:space, :name => 'Be space')
        }
        before(:each) { get :spaces }
        it { assigns(:spaces).count.should be(4) }
        it { assigns(:spaces)[0].should eql(@s3) }
        it { assigns(:spaces)[1].should eql(@s4) }
        it { assigns(:spaces)[2].should eql(@s2) }
        it { assigns(:spaces)[3].should eql(@s1) }
      end

      context "paginates the list of spaces" do
        before {
          45.times { FactoryGirl.create(:space) }
        }

        context "if no page is passed in params" do
          before(:each) { get :spaces }
          it { assigns(:spaces).size.should be(20) }
          it { controller.params[:page].should be_nil }
        end

        context "if a page is passed in params" do
          before(:each) { get :spaces, :page => 2 }
          it { assigns(:spaces).size.should be(20) }
          it("includes the correct spaces in @spaces") {
            page = Space.order('name').paginate(:page => 2, :per_page => 20)
            page.each do |space|
              assigns(:spaces).should include(space)
            end
          }
          it { controller.params[:page].should eql("2") }
        end
      end

      context "use params[:q] to filter the results" do
        context "by name" do
          before {
            @s1 = FactoryGirl.create(:space, :name => 'First')
            @s2 = FactoryGirl.create(:space, :name => 'Second')
            @s3 = FactoryGirl.create(:space, :name => 'Secondary')
          }
          before(:each) { get :spaces, :q => 'sec' }
          it { assigns(:spaces).count.should be(2) }
          it { assigns(:spaces).should include(@s2) }
          it { assigns(:spaces).should include(@s3) }
        end
      end

      context "use params [:approved, :disabled] to filter the results" do
        let!(:spaces) {[
            FactoryGirl.create(:space, :name => 'Approved', :approved => true),
            FactoryGirl.create(:space, :name => 'Not Approved', :approved => false),
            FactoryGirl.create(:space, :name => 'Enabled', :disabled => false),
            FactoryGirl.create(:space, :name => 'Disabled', :disabled => true)
        ]}
        before {
          spaces[1].disapprove!
          get :spaces, params
        }

        context "no params" do
          let(:params) { {} }

          it { assigns(:spaces).count.should be(4) }
          it { assigns(:spaces).should include(*spaces) }
        end

        context "params[:approved]" do
          context 'is true' do
            let(:params) { {approved: 'true'} }
            it { assigns(:spaces).count.should be(3) }
            it { assigns(:spaces).should include(spaces[0], spaces[2], spaces[3]) }
          end

          context 'is false' do
            let(:params) { {approved: 'false'} }
            it { assigns(:spaces).count.should be(1) }
            it { assigns(:spaces).should include(spaces[1]) }
          end
        end

        context "params[:disabled]" do
          context 'is true' do
            let(:params) { {disabled: 'true'} }
            it { assigns(:spaces).count.should be(1) }
            it { assigns(:spaces).should include(spaces[3]) }
          end

          context 'is false' do
            let(:params) { {disabled: 'false'} }
            it { assigns(:spaces).count.should be(3) }
            it { assigns(:spaces).should include(spaces[0], spaces[1], spaces[2]) }
          end
        end

        context "mixed params" do
          let(:params) { {approved: 'true', disabled: 'false', q: 'Ena'} }

          it { assigns(:spaces).count.should be(1) }
          it { assigns(:spaces).should include(spaces[2]) }
        end
      end

      context "if xhr request" do
        before(:each) { xhr :get, :spaces }
        it { should render_template('manage/_spaces_list') }
        it { should_not render_with_layout }
      end

      context "not xhr request" do
        before(:each) { get :spaces }
        it { should render_template(:spaces) }
        it { should render_with_layout('no_sidebar') }
      end
    end
  end

  describe "abilities", :abilities => true do
    render_views(false)

    context "for a superuser", :user => "superuser" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { login_as(user) }
      it { should allow_access_to(:users) }
      it { should allow_access_to(:spaces) }
    end

    context "for a normal user", :user => "normal" do
      let(:user) { FactoryGirl.create(:user) }
      before(:each) { login_as(user) }
      it { should_not allow_access_to(:users) }
      it { should_not allow_access_to(:spaces) }
    end

    context "for an anonymous user", :user => "anonymous" do
      it { should_not allow_access_to(:users) }
      it { should_not allow_access_to(:spaces) }
    end
  end

  describe "#recordings" do
    it "should require authentication"

    context "authorizes" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { sign_in(user) }
      it { should_authorize :manage, :recordings }
    end

    describe "if the current user is a superuser" do
      let(:user) { FactoryGirl.create(:superuser) }
      before(:each) { sign_in(user) }

      it {
        get :recordings
        should respond_with(:success)
      }

      context "sets @recordings to a list of all recordings, including not available recordings" do
        before {
          @s1 = FactoryGirl.create(:bigbluebutton_recording, :available => true)
          @s2 = FactoryGirl.create(:bigbluebutton_recording, :available => true)
          @s3 = FactoryGirl.create(:bigbluebutton_recording, :available => false)
        }
        before(:each) { get :recordings }
        it { assigns(:recordings).count.should be(3) }
        it { assigns(:recordings).should include(@s1) }
        it { assigns(:recordings).should include(@s2) }
        it { assigns(:recordings).should include(@s3) }
      end

      context "orders @recordings by start_time" do
        before {
          @s1 = FactoryGirl.create(:bigbluebutton_recording, start_time: DateTime.now - 3.days)
          @s2 = FactoryGirl.create(:bigbluebutton_recording, start_time: DateTime.now - 2.days)
          @s3 = FactoryGirl.create(:bigbluebutton_recording, start_time: DateTime.now)
          @s4 = FactoryGirl.create(:bigbluebutton_recording, start_time: DateTime.now - 1.days)
        }
        before(:each) { get :recordings }
        it { assigns(:recordings).count.should be(4) }
        it { assigns(:recordings)[0].should eql(@s3) }
        it { assigns(:recordings)[1].should eql(@s4) }
        it { assigns(:recordings)[2].should eql(@s2) }
        it { assigns(:recordings)[3].should eql(@s1) }
      end

      context "paginates the list of recordings" do
        before {
          45.times { FactoryGirl.create(:bigbluebutton_recording) }
        }

        context "if no page is passed in params" do
          before(:each) { get :recordings }
          it { assigns(:recordings).size.should be(20) }
          it { controller.params[:page].should be_nil }
        end

        context "if a page is passed in params" do
          before(:each) { get :recordings, :page => 2 }
          it { assigns(:recordings).size.should be(20) }
          it("includes the correct recordings in @recordings") {
            page = BigbluebuttonRecording.order('start_time DESC').paginate(page: 2, per_page: 20)
            page.each do |recording|
              assigns(:recordings).should include(recording)
            end
          }
          it { controller.params[:page].should eql("2") }
        end
      end

      context "use params[:q] to filter the results" do

        context "by name" do
          before {
            @r1 = FactoryGirl.create(:bigbluebutton_recording, :name => 'First')
            @r2 = FactoryGirl.create(:bigbluebutton_recording, :name => 'Second')
            @r3 = FactoryGirl.create(:bigbluebutton_recording, :name => 'Secondary')
          }
          before(:each) { get :recordings, :q => 'second' }
          it { assigns(:recordings).count.should be(2) }
          it { assigns(:recordings).should include(@r2) }
          it { assigns(:recordings).should include(@r3) }
        end

        context "by description" do
          before {
            @r1 = FactoryGirl.create(:bigbluebutton_recording, :description => 'First description')
            @r2 = FactoryGirl.create(:bigbluebutton_recording, :description => 'Second description')
            @r3 = FactoryGirl.create(:bigbluebutton_recording, :description => 'Secondary description')
          }
          before(:each) { get :recordings, :q => 'second' }
          it { assigns(:recordings).count.should be(2) }
          it { assigns(:recordings).should include(@r2) }
          it { assigns(:recordings).should include(@r3) }
        end

        context "by record id" do
          before {
            @r1 = FactoryGirl.create(:bigbluebutton_recording, :recordid => 'First recordid')
            @r2 = FactoryGirl.create(:bigbluebutton_recording, :recordid => 'Second recordid')
            @r3 = FactoryGirl.create(:bigbluebutton_recording, :recordid => 'Secondary recordid')
          }
          before(:each) { get :recordings, :q => 'second' }
          it { assigns(:recordings).count.should be(2) }
          it { assigns(:recordings).should include(@r2) }
          it { assigns(:recordings).should include(@r3) }
        end

      end

      context "use params [:published, :available, :playback] to filter the results" do
        let!(:playback_formats) {[
          FactoryGirl.create(:bigbluebutton_playback_format, recording: FactoryGirl.create(:bigbluebutton_recording, name: 'has_playback_rec'))
        ]}
        let!(:recordings) {[
          FactoryGirl.create(:bigbluebutton_recording, name: 'published_rec'),
          FactoryGirl.create(:bigbluebutton_recording, name: 'unpublished_rec', published: false),
          FactoryGirl.create(:bigbluebutton_recording, name: 'unavailable_rec', available: false),
          playback_formats[0].recording,
          FactoryGirl.create(:bigbluebutton_recording, name: 'no_playback_rec'),
        ]}

        before {
          get :recordings, params
        }

        context "no params" do
          let(:params) { {} }

          it { assigns(:recordings).count.should be(5) }
          it { assigns(:recordings).should include(*recordings) }
        end

        context "params[:published]" do
          context 'is true' do
            let(:params) { {published: 'true'} }
            it { assigns(:recordings).count.should be(4) }
            it { assigns(:recordings).should include(recordings[0], recordings[2], recordings[3], recordings[4]) }
          end

          context 'is false' do
            let(:params) { {published: 'false'} }
            it { assigns(:recordings).count.should be(1) }
            it { assigns(:recordings).should include(recordings[1]) }
          end
        end

        context "params[:available]" do
          context 'is true' do
            let(:params) { {available: 'true'} }
            it { assigns(:recordings).count.should be(4) }
            it { assigns(:recordings).should include(recordings[0], recordings[1], recordings[3], recordings[4]) }
          end

          context 'is false' do
            let(:params) { {available: 'false'} }
            it { assigns(:recordings).count.should be(1) }
            it { assigns(:recordings).should include(recordings[2]) }
          end
        end

        context "params[:playback]" do
          context 'is true' do
            let(:params) { {playback: 'true'} }
            it { assigns(:recordings).count.should be(1) }
            it { assigns(:recordings).should include(recordings[3]) }
          end

          context 'is false' do
            let(:params) { {playback: 'false'} }
            it { assigns(:recordings).count.should be(4) }
            it { assigns(:recordings).should include(recordings[0], recordings[1], recordings[2], recordings[4]) }
          end
        end

        context "mixed params" do
          let(:params) { {published: 'true', available: 'true', q: 'rec'} }

          it { assigns(:recordings).count.should be(3) }
          it { assigns(:recordings).should include(recordings[0], recordings[3], recordings[4]) }
        end
      end

      context "if xhr request" do
        before(:each) { xhr :get, :recordings }
        it { should render_template('manage/_recordings_list') }
        it { should_not render_with_layout }
      end

      context "not xhr request" do
        before(:each) { get :recordings }
        it { should render_template(:recordings) }
        it { should render_with_layout('no_sidebar') }
      end
    end
  end
end
