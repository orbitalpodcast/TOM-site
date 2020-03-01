require 'test_helper'

class PublishFlowTest < ActionDispatch::IntegrationTest
  setup do
    TITLE_REGEX = /(Episode [0-9]{3}: )(DOWNLINK--|DATA RELAY--){0,1}[\w\s]*/
    @episode = {newsletter_status: 'not sent',
                draft: false,
                publish_date: '2019-9-8',
                number: 231,
                title: 'Fewer gyros, more problems',
                slug: 'fewer-gyros-more-problems',
                description: "DSCOVR's safehold seems to be connected to a gryo, but there's a fix coming down the line.",
                notes: "This week in SF history
                * 2000 October 9: HETE-2, first orbital launch from Kwajalein https://en.wikipedia.org/wiki/High_Energy_Transient_Explorer
                * Next week in 1956: listen in for an audio clue.
                Spaceflight News
                * Plans in place to fix DSCOVR https://spacenews.com/software-fix-planned-to-restore-dscovr/
                ** We first reported on this on Ep 218 as an S&S https://spacenews.com/dscovr-spacecraft-in-safe-mode/
                ** Faulty gyro? https://twitter.com/simoncarn/status/1175823150984126464
                *** Triana engineers considered laser gyro failures PDF: https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/20010084979.pdf
                Short & Sweet
                * NASA Mars 2020 tests descent stage separation https://www.jpl.nasa.gov/news/news.php?feature=7513\
                * NASA issues request for information on xEMU. https://www.nasaspaceflight.com/2019/10/nasa-rfi-new-lunar-spacesuits/
                * New Shepard will likely not fly humans in 2019. https://spacenews.com/blue-origin-may-miss-goal-of-crewed-suborbital-flights-in-2019/
                Questions, comments, corrections
                * https://twitter.com/search?q=\%23tomiac2019&amp;f=live\
                ** Sunday: Off Nominal meetups https://events.offnominal.space/
                ** Monday: museum day
                *** Udvar-Hazy and downtown Air and Space Museum
                ** Thursday: Dinner meetup
                *** https://www.mcgintyspublichouse.com/
                *** 911 Ellsworth Dr, Silver Spring, MD 20910
                ** Friday: IAC no-ticket open day"}
    @ep_draft = {newsletter_status: 'not sent',
                draft: true,
                publish_date: '1-7-2020',
                number: 242,
                title: 'DOWNLINK--Dr. Martin Elvis',
                slug: 'martin-elvis',
                description: "Asteroid mining is often discussed in terms of engineering and economics. Today, we're talking about raw material availability.",
                notes: "Spaceflight news
                        *ISRO confirms plans for Chandrayaan-3 (spacenews.com)
                        **Chandrayaan-2 imagery (nasa.gov)
                        Short & Sweet
                        *SpaceX plans a moveable tower for pad 39A (spaceflightnow.com)
                        *Christina Koch breaks a record (spaceflightnow.com)
                        *Early signs of the Clean Space age: Iridium announces willingness to pay for third party cleanup of failed satellites (spacenews.com)
                        Interview: Dr. Martin Elvis, Senior Astrophysicist, Center for Astrophysics and Smithsonian
                        *harvard.edu/~elvis
                        *Simulated population of asteroids from mikael granvik (helsinki.fi)
                        This week in SF history
                        *10 January 2015: first droneship landing attempt (wikipedia.org)
                        *Next week in 1977: black side down"}
    ENV['test_skip_authorized'] = 'true'
  end

  test 'Reverting publish flow for invalid episode' do
    post login_path, params: {email: users(:admin).email, password: 'VSkI3n&r0Q9k2XFZGxUi'}

    # Create new episode
    ep = {newsletter_status: 'not scheduled',
          draft: true,
          slug: '',
          title: '',
          description: '',
          notes: '',
          number: @episode[:number]}
    assert_difference('Episode.count') do
      post episodes_url, params: {episode: ep, commit: "Save as draft"}
    end
    assert_equal 'Episode draft was successfully created.', flash[:notice]

    # Update attributes, with missing description
    ep = @episode.clone
    ep[:description] = ''
    assert_no_difference('Episode.count') do
      patch episode_url ep[:number], params: {episode: ep, commit: "Save as draft"}
    end
    assert_equal 'Episode draft was successfully updated.', flash[:notice]
    assert_select "textarea[id=episode_notes]", ep[:notes]

    # Try to publish
    patch episode_url ep[:number], params: {episode: ep, commit: "Publish"}
    assert_match /Can't publish if the newsletter hasn\'t been handled./,
        assigns(:episode).errors.full_messages.first

    # Change the description, then try to publish again. Test that the change was persisted.
    ep[:description] = @episode[:description]
    patch episode_url ep[:number], params: {episode: ep, commit: "Publish"}
    assert_match /Can't publish if the newsletter hasn\'t been handled./,
        assigns(:episode).errors.full_messages.first
    assert_select "input[id=episode_description]" do
      assert_select '[value=?]', ep[:description]
    end
    assert_select 'div.field' do
      assert_select 'strong', 'true'
    end
  end

  # test 'Warning for missing images during publish flow' do
  # end

  # test 'Overriding newsletter during publish flow' do
  # end

  # test 'Overriding socials during publish flow' do
  # end

end